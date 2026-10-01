#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "polars==1.43.2",
#   "pysam==0.23.3",
# ]
# ///

"""Summarize per-reference mapping coverage without expanding aligned bases."""

import argparse
import csv
import json
import platform
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import polars as pl
import pysam

BATCH_SIZE = 10_000
CIGAR_COVERAGE_OPERATIONS = frozenset({0, 7, 8})
CIGAR_REFERENCE_OPERATIONS = frozenset({0, 2, 3, 7, 8})
BLOCK_SCHEMA = {
    "qname": pl.String,
    "reference_id": pl.String,
    "start": pl.Int64,
    "end": pl.Int64,
}
PLACEMENT_SCHEMA = {
    "qname": pl.String,
    "reference_id": pl.String,
    "is_primary": pl.Boolean,
}
REFERENCE_SCHEMA = {
    "reference_id": pl.String,
    "reference_name": pl.String,
    "reference_length": pl.Int64,
}


@dataclass(frozen=True)
class Args:
    """Command-line configuration for one sample-local mapping comparison."""

    bam: Path
    fasta: Path
    profile: Path
    counts: Path
    profile_read_set: str
    mapped_read_set: str
    sylph_estimate_read_counts: bool
    coverage_output: Path
    intervals_output: Path
    versions_output: Path
    process: str


@dataclass(frozen=True)
class CoverageViews:
    """Lazy all-placement and exclusive-read coverage views."""

    placements: pl.LazyFrame
    all_unioned: pl.LazyFrame
    all_intervals: pl.LazyFrame
    exclusive_unioned: pl.LazyFrame
    exclusive_intervals: pl.LazyFrame


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bam", required=True, type=Path)
    parser.add_argument("--fasta", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--counts", required=True, type=Path)
    parser.add_argument("--profile-read-set", required=True)
    parser.add_argument("--mapped-read-set", required=True)
    parser.add_argument(
        "--sylph-estimate-read-counts",
        action="store_true",
        help=(
            "Source Sylph profile used --estimate-read-counts "
            "(default: percentage units)"
        ),
    )
    parser.add_argument("--coverage-output", required=True, type=Path)
    parser.add_argument("--intervals-output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        bam=namespace.bam,
        fasta=namespace.fasta,
        profile=namespace.profile,
        counts=namespace.counts,
        profile_read_set=namespace.profile_read_set,
        mapped_read_set=namespace.mapped_read_set,
        sylph_estimate_read_counts=namespace.sylph_estimate_read_counts,
        coverage_output=namespace.coverage_output,
        intervals_output=namespace.intervals_output,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def fasta_references(path: Path) -> Iterator[tuple[str, str, int]]:
    """Stream FASTA headers and lengths while retaining full-header association."""
    reference_id: str | None = None
    reference_name: str | None = None
    reference_length = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith(">"):
                if reference_id is not None and reference_name is not None:
                    yield reference_id, reference_name, reference_length
                reference_name = line[1:].rstrip("\r\n")
                reference_id = reference_name.split(maxsplit=1)[0]
                reference_length = 0
            else:
                reference_length += len(line.strip())
    if reference_id is not None and reference_name is not None:
        yield reference_id, reference_name, reference_length


def write_references(fasta: Path, output: Path) -> None:
    """Write selected references as a tabular stream for lazy joins."""
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(REFERENCE_SCHEMA)
        writer.writerows(fasta_references(fasta))


def cigar_blocks(read: pysam.AlignedSegment) -> Iterator[tuple[str, str, int, int]]:
    """Yield only M, =, and X reference intervals for one mapped alignment."""
    reference_id = read.reference_name
    qname = read.query_name
    if reference_id is None or qname is None or read.cigartuples is None:
        return
    position = read.reference_start
    for operation, length in read.cigartuples:
        if operation in CIGAR_COVERAGE_OPERATIONS:
            yield qname, reference_id, position, position + length
        if operation in CIGAR_REFERENCE_OPERATIONS:
            position += length


def placement(read: pysam.AlignedSegment) -> tuple[str, str, bool] | None:
    """Return one reported-reference relation even when an alignment covers no bases."""
    if read.is_unmapped or read.query_name is None or read.reference_name is None:
        return None
    is_primary = not read.is_secondary and not read.is_supplementary
    return read.query_name, read.reference_name, is_primary


def write_evidence(bam: Path, blocks_output: Path, placements_output: Path) -> None:
    """Materialize bounded CIGAR blocks and all mapped reference relations together."""
    with (
        blocks_output.open("w", encoding="utf-8", newline="") as blocks_handle,
        placements_output.open("w", encoding="utf-8", newline="") as placements_handle,
        pysam.AlignmentFile(str(bam), "rb") as alignments,
    ):
        blocks_writer = csv.writer(blocks_handle, delimiter="\t", lineterminator="\n")
        placements_writer = csv.writer(
            placements_handle,
            delimiter="\t",
            lineterminator="\n",
        )
        blocks_writer.writerow(BLOCK_SCHEMA)
        placements_writer.writerow(PLACEMENT_SCHEMA)
        blocks_batch: list[tuple[str, str, int, int]] = []
        placements_batch: list[tuple[str, str, bool]] = []
        for read in alignments.fetch(until_eof=True):
            if relation := placement(read):
                placements_batch.append(relation)
                blocks_batch.extend(cigar_blocks(read))
            if len(blocks_batch) >= BATCH_SIZE:
                blocks_writer.writerows(blocks_batch)
                blocks_batch.clear()
            if len(placements_batch) >= BATCH_SIZE:
                placements_writer.writerows(placements_batch)
                placements_batch.clear()
        blocks_writer.writerows(blocks_batch)
        placements_writer.writerows(placements_batch)


def union_read_blocks(blocks: pl.LazyFrame) -> pl.LazyFrame:
    """Union overlapping blocks per read and reference before depth aggregation."""
    keys = ["qname", "reference_id"]
    ordered = blocks.sort([*keys, "start", "end"]).with_columns(
        pl.col("end").cum_max().shift(1).over(keys).alias("previous_end"),
    )
    grouped = ordered.with_columns(
        pl.when(
            pl.col("previous_end").is_null()
            | (pl.col("start") > pl.col("previous_end")),
        )
        .then(pl.lit(1))
        .otherwise(pl.lit(0))
        .alias("new_interval"),
    ).with_columns(
        pl.col("new_interval").cum_sum().over(keys).alias("interval_group"),
    )
    return grouped.group_by([*keys, "interval_group"]).agg(
        pl.col("start").min().alias("start"),
        pl.col("end").max().alias("end"),
    )


def depth_intervals(unioned: pl.LazyFrame) -> pl.LazyFrame:
    """Turn read-unioned intervals into weighted-depth spans with endpoint events."""
    events = (
        pl.concat(
            [
                unioned.select("reference_id", "start")
                .rename({"start": "position"})
                .with_columns(pl.lit(1).alias("delta")),
                unioned.select("reference_id", "end")
                .rename({"end": "position"})
                .with_columns(pl.lit(-1).alias("delta")),
            ],
        )
        .group_by(["reference_id", "position"])
        .agg(pl.col("delta").sum())
    )
    return (
        events.sort(["reference_id", "position"])
        .with_columns(
            pl.col("delta").cum_sum().over("reference_id").alias("depth"),
            pl.col("position").shift(-1).over("reference_id").alias("end"),
        )
        .filter(
            (pl.col("depth") > 0)
            & pl.col("end").is_not_null()
            & (pl.col("position") < pl.col("end")),
        )
        .select(
            "reference_id",
            pl.col("position").alias("start"),
            "end",
            "depth",
        )
    )


def distinct_reference_placements(placements: pl.LazyFrame) -> pl.LazyFrame:
    """Label each reported placement by its read's distinct reference count."""
    return (
        placements.select("qname", "reference_id")
        .unique()
        .with_columns(
            pl.len().over("qname").alias("reported_reference_count"),
        )
    )


def ensure_primary_names(placements: pl.LazyFrame) -> None:
    """Reject repeated mapped primaries before collapsing placements by QNAME."""
    duplicates = (
        placements.filter(pl.col("is_primary"))
        .group_by("qname")
        .agg(pl.len().alias("primaries"))
        .filter(pl.col("primaries") > 1)
        .select("qname")
        .limit(1)
        .collect()
    )
    if duplicates.height:
        message = f"Multiple primary mapped records for QNAME {duplicates.item()!r}."
        raise SystemExit(message)


def coverage_views(blocks: pl.LazyFrame, placements: pl.LazyFrame) -> CoverageViews:
    """Derive all-supporting and exclusive-read coverage lazily."""
    classified = distinct_reference_placements(placements)
    exclusive_qnames = classified.filter(
        pl.col("reported_reference_count") == 1,
    ).select("qname")
    all_unioned = union_read_blocks(blocks)
    exclusive_unioned = union_read_blocks(
        blocks.join(exclusive_qnames, on="qname", how="inner"),
    )
    return CoverageViews(
        placements=classified,
        all_unioned=all_unioned,
        all_intervals=depth_intervals(all_unioned),
        exclusive_unioned=exclusive_unioned,
        exclusive_intervals=depth_intervals(exclusive_unioned),
    )


def support_counts(placements: pl.LazyFrame) -> pl.LazyFrame:
    """Count each read once per reference: exclusive at one, shared at multiple."""
    return placements.group_by("reference_id").agg(
        pl.col("qname").n_unique().alias("supporting_read_count"),
        pl.col("qname")
        .filter(pl.col("reported_reference_count") == 1)
        .n_unique()
        .alias("exclusive_read_count"),
        pl.col("qname")
        .filter(pl.col("reported_reference_count") > 1)
        .n_unique()
        .alias("shared_read_count"),
    )


def depth_metrics(intervals: pl.LazyFrame, prefix: str) -> pl.LazyFrame:
    """Aggregate breadth numerator and weighted depth under a metric prefix."""
    return intervals.group_by("reference_id").agg(
        (pl.col("end") - pl.col("start")).sum().alias(f"{prefix}covered_bases"),
        ((pl.col("end") - pl.col("start")) * pl.col("depth"))
        .sum()
        .alias(f"{prefix}depth_bases"),
    )


def profile_comparison(profile: Path) -> pl.LazyFrame:
    """Select the unmodified Sylph comparison values from the source profile."""
    source = pl.scan_csv(profile, separator="\t", infer_schema=False)
    required = {"Contig_name", "Sequence_abundance", "Adjusted_ANI"}
    missing = sorted(required - set(source.collect_schema().names()))
    if missing:
        message = f"Sylph profile is missing comparison column(s): {', '.join(missing)}"
        raise SystemExit(message)
    columns = set(source.collect_schema().names())
    return source.select(
        pl.col("Contig_name").alias("reference_name"),
        *(
            (pl.col(name) if name in columns else pl.lit(None, dtype=pl.String)).alias(
                name,
            )
            for name in (
                "Taxonomic_abundance",
                "Sequence_abundance",
                "Adjusted_ANI",
                "Eff_cov",
                "True_cov",
            )
        ),
    )


def mapper_counts(path: Path) -> tuple[int, int]:
    """Read the small mapper-produced denominator record."""
    values = json.loads(path.read_text(encoding="utf-8"))
    return int(values["total_reads"]), int(values["mapped_reads"])


def coverage_table(
    references: pl.LazyFrame,
    profile: pl.LazyFrame,
    views: CoverageViews,
    args: Args,
) -> pl.LazyFrame:
    """Join profile evidence and zero-hit selected references to coverage metrics."""
    total_reads, mapped_reads = mapper_counts(args.counts)
    all_depth = depth_metrics(views.all_intervals, "")
    exclusive_depth = depth_metrics(views.exclusive_intervals, "exclusive_")
    joined = references.join(profile, on="reference_name", how="left")
    joined = joined.join(
        support_counts(views.placements),
        on="reference_id",
        how="left",
    )
    return (
        joined.join(all_depth, on="reference_id", how="left")
        .join(exclusive_depth, on="reference_id", how="left")
        .with_columns(
            pl.col("supporting_read_count").fill_null(0).cast(pl.Int64),
            pl.col("exclusive_read_count").fill_null(0).cast(pl.Int64),
            pl.col("shared_read_count").fill_null(0).cast(pl.Int64),
            pl.col("covered_bases").fill_null(0).cast(pl.Int64),
            pl.col("depth_bases").fill_null(0).cast(pl.Int64),
            pl.col("exclusive_covered_bases").fill_null(0).cast(pl.Int64),
            pl.col("exclusive_depth_bases").fill_null(0).cast(pl.Int64),
        )
        .with_columns(
            pl.lit(total_reads).alias("total_read_count"),
            pl.lit(mapped_reads).alias("mapper_mapped_read_count"),
            pl.lit(args.profile_read_set).alias("profiling_read_set"),
            pl.lit(args.mapped_read_set).alias("mapped_read_set"),
            pl.lit(
                "estimated_reads" if args.sylph_estimate_read_counts else "percent",
            ).alias(
                "sylph_sequence_abundance_units",
            ),
        )
        .with_columns(
            pl.when(pl.col("total_read_count") > 0)
            .then(pl.col("supporting_read_count") / pl.col("total_read_count"))
            .otherwise(pl.lit(0.0))
            .alias("mapped_read_fraction"),
            (pl.col("covered_bases") / pl.col("reference_length")).alias("breadth"),
            (pl.col("depth_bases") / pl.col("reference_length")).alias("mean_depth"),
            (pl.col("exclusive_covered_bases") / pl.col("reference_length")).alias(
                "exclusive_breadth",
            ),
            (pl.col("exclusive_depth_bases") / pl.col("reference_length")).alias(
                "exclusive_mean_depth",
            ),
        )
        .select(
            "reference_id",
            "reference_name",
            "reference_length",
            "profiling_read_set",
            "mapped_read_set",
            "Taxonomic_abundance",
            "Sequence_abundance",
            "sylph_sequence_abundance_units",
            "Adjusted_ANI",
            "Eff_cov",
            "True_cov",
            "total_read_count",
            "mapper_mapped_read_count",
            "supporting_read_count",
            "exclusive_read_count",
            "shared_read_count",
            "mapped_read_fraction",
            "covered_bases",
            "breadth",
            "mean_depth",
            "exclusive_breadth",
            "exclusive_mean_depth",
        )
        .sort("reference_id")
    )


def write_versions(path: Path, process: str) -> None:
    """Write native dependency versions in nf-core versions-file form."""
    path.write_text(
        f'"{process}":\n'
        f'    polars: "{pl.__version__}"\n'
        f'    pysam: "{pysam.__version__}"\n'
        f'    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    """Decode CIGAR blocks, then lazily calculate unioned coverage and comparisons."""
    args = parse_args()
    blocks_path = args.coverage_output.with_name("mapping-cigar-blocks.tsv")
    placements_path = args.coverage_output.with_name("mapping-placements.tsv")
    references_path = args.coverage_output.with_name("mapping-references.tsv")
    write_evidence(args.bam, blocks_path, placements_path)
    write_references(args.fasta, references_path)
    blocks = pl.scan_csv(blocks_path, separator="\t", schema=BLOCK_SCHEMA)
    placements = pl.scan_csv(placements_path, separator="\t", schema=PLACEMENT_SCHEMA)
    ensure_primary_names(placements)
    references = pl.scan_csv(references_path, separator="\t", schema=REFERENCE_SCHEMA)
    views = coverage_views(blocks, placements)
    coverage_table(
        references,
        profile_comparison(args.profile),
        views,
        args,
    ).sink_csv(args.coverage_output, separator="\t")
    views.all_intervals.join(references, on="reference_id", how="inner").select(
        "reference_id",
        "reference_name",
        "start",
        "end",
        "depth",
    ).sort(["reference_id", "start"]).sink_csv(args.intervals_output, separator="\t")
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
