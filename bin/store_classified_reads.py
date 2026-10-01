#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "polars==1.43.2",
#   "pysam==0.23.3",
# ]
# ///

"""Store classified read payloads and reported BAM placements as Parquet."""

import argparse
import gzip
import platform
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path

import polars as pl
import pysam
from stream_mapping_reads import mapper_name

BATCH_SIZE = 100_000
BATCH_BYTES = 8 * 1024 * 1024
type AlignmentRow = tuple[
    str,
    str,
    str,
    int,
    bool,
    bool,
    bool,
    str,
    int,
    int | None,
    str | None,
    int,
    int | None,
]
type PayloadRow = tuple[str, str, str, str, str]
ALIGNMENT_SCHEMA = {
    "read_key": pl.String,
    "mapped_qname": pl.String,
    "reference_id": pl.String,
    "flag": pl.Int64,
    "is_secondary": pl.Boolean,
    "is_supplementary": pl.Boolean,
    "is_primary": pl.Boolean,
    "strand": pl.String,
    "start": pl.Int64,
    "end": pl.Int64,
    "cigar": pl.String,
    "mapq": pl.Int64,
    "alignment_score": pl.Int64,
}
PAYLOAD_SCHEMA = {
    "read_key": pl.String,
    "original_header": pl.String,
    "sequence": pl.String,
    "quality": pl.String,
    "plus_line": pl.String,
}
REFERENCE_SCHEMA = {"reference_id": pl.String, "reference_name": pl.String}


@dataclass(frozen=True)
class Args:
    """Command-line configuration for one mapped read set and reference spec."""

    bam: Path
    fasta: Path
    inputs: tuple[Path, ...]
    output: Path
    sample_id: str
    mapped_read_set: str
    reference_specification: str
    allowlist: Path | None
    versions_output: Path
    process: str


@dataclass(frozen=True)
class FastqRecord:
    """One unwrapped FASTQ record retaining the user-visible record content."""

    header: str
    sequence: str
    quality: str
    plus_line: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bam", required=True, type=Path)
    parser.add_argument("--fasta", required=True, type=Path)
    parser.add_argument("--input", action="append", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sample-id", required=True)
    parser.add_argument("--mapped-read-set", required=True)
    parser.add_argument("--reference-specification", required=True)
    parser.add_argument("--allowlist", type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        bam=namespace.bam,
        fasta=namespace.fasta,
        inputs=tuple(namespace.input),
        output=namespace.output,
        sample_id=namespace.sample_id,
        mapped_read_set=namespace.mapped_read_set,
        reference_specification=namespace.reference_specification,
        allowlist=namespace.allowlist,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def write_references(fasta: Path, output: Path) -> None:
    """Write BAM reference IDs with their selected FASTA full-header associations."""
    rows: list[tuple[str, str]] = []
    with fasta.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith(">"):
                name = line[1:].rstrip("\r\n")
                rows.append((name.split(maxsplit=1)[0], name))
    pl.DataFrame(rows, schema=REFERENCE_SCHEMA, orient="row").write_parquet(output)


def alignment_row(read: pysam.AlignedSegment) -> AlignmentRow | None:
    """Convert one reported mapped BAM record into compact placement metadata."""
    if read.is_unmapped or read.query_name is None or read.reference_name is None:
        return None
    return (
        read.query_name,
        read.query_name,
        read.reference_name,
        read.flag,
        read.is_secondary,
        read.is_supplementary,
        not read.is_secondary and not read.is_supplementary,
        "-" if read.is_reverse else "+",
        read.reference_start,
        read.reference_end,
        read.cigarstring,
        read.mapping_quality,
        int(read.get_tag("AS")) if read.has_tag("AS") else None,
    )


def write_alignment_batches(bam: Path, directory: Path) -> None:
    """Stream BAM metadata into bounded native Parquet batches after alignment."""
    directory.mkdir()
    batch: list[AlignmentRow] = []
    index = 0
    with pysam.AlignmentFile(str(bam), "rb") as alignments:
        for read in alignments.fetch(until_eof=True):
            if row := alignment_row(read):
                batch.append(row)
            if len(batch) >= BATCH_SIZE:
                frame = pl.DataFrame(batch, schema=ALIGNMENT_SCHEMA, orient="row")
                frame.write_parquet(
                    directory / f"{index:06}.parquet",
                )
                batch.clear()
                index += 1
    pl.DataFrame(batch, schema=ALIGNMENT_SCHEMA, orient="row").write_parquet(
        directory / f"{index:06}.parquet",
    )


def fastq_records(path: Path) -> Iterator[FastqRecord]:
    """Parse wrapped FASTQ while retaining full headers and plus-line content.

    pysam exposes decoded records but discards the original plus line, so this small
    boundary parser is deliberately limited to record framing and unwrapping.
    """
    opener = gzip.open if path.suffix == ".gz" else Path.open
    with opener(path, "rt", encoding="utf-8", newline="") as handle:
        header = handle.readline()
        while header:
            if not header.startswith("@"):
                message = f"FASTQ record in {path} does not start with '@'."
                raise SystemExit(message)
            sequence_lines: list[str] = []
            line = handle.readline()
            while line and not line.startswith("+"):
                sequence_lines.append(line.rstrip("\r\n"))
                line = handle.readline()
            if not line:
                message = f"FASTQ record in {path} is missing its plus line."
                raise SystemExit(message)
            sequence = "".join(sequence_lines)
            plus_line = line[1:].rstrip("\r\n")
            quality_lines: list[str] = []
            quality_length = 0
            while quality_length < len(sequence):
                line = handle.readline()
                if not line:
                    message = f"FASTQ record in {path} is missing quality content."
                    raise SystemExit(message)
                quality_line = line.rstrip("\r\n")
                quality_lines.append(quality_line)
                quality_length += len(quality_line)
            if quality_length != len(sequence):
                message = f"FASTQ sequence/quality lengths differ in {path}."
                raise SystemExit(message)
            yield FastqRecord(
                header=header[1:].rstrip("\r\n"),
                sequence=sequence,
                quality="".join(quality_lines),
                plus_line=plus_line,
            )
            header = handle.readline()


def payload_rows(
    inputs: Sequence[Path],
) -> Iterator[PayloadRow]:
    """Stream original record payloads with the exact mapper naming policy."""
    for path in inputs:
        for record in fastq_records(path):
            yield (
                mapper_name(record.header),
                record.header,
                record.sequence,
                record.quality,
                record.plus_line,
            )


def payload_size(row: PayloadRow) -> int:
    """Measure one uncompressed payload row for a bounded parser batch."""
    return sum(len(value.encode("utf-8")) for value in row)


def matching_payloads(
    batch: list[PayloadRow], needed_reads: pl.DataFrame
) -> pl.DataFrame:
    """Semi-join one bounded payload batch with retained mapper identities."""
    frame = pl.DataFrame(batch, schema=PAYLOAD_SCHEMA, orient="row")
    return frame.lazy().join(needed_reads.lazy(), on="read_key", how="semi").collect()


def write_matching_payload_batches(
    inputs: Sequence[Path],
    needed_reads: pl.DataFrame,
    directory: Path,
) -> None:
    """Keep only BAM-reported payload batches through native semi-joins.

    ``needed_reads`` is the one O(retained read keys) metadata object; no original
    payloads outside the current bounded batch are retained in Python memory.
    """
    directory.mkdir()
    batch: list[PayloadRow] = []
    batch_bytes = 0
    index = 0
    for row in payload_rows(inputs):
        batch.append(row)
        batch_bytes += payload_size(row)
        if len(batch) >= BATCH_SIZE or batch_bytes >= BATCH_BYTES:
            matching = matching_payloads(batch, needed_reads)
            if matching.height:
                matching.write_parquet(directory / f"{index:06}.parquet")
                index += 1
            batch.clear()
            batch_bytes = 0
    if batch:
        matching = matching_payloads(batch, needed_reads)
        if matching.height:
            matching.write_parquet(directory / f"{index:06}.parquet")


def selected_alignments(
    alignments: pl.LazyFrame,
    allowlist: Path | None,
) -> pl.LazyFrame:
    """Apply exact-reference existential filtering while retaining every placement."""
    if allowlist is None:
        return alignments
    if allowlist.stat().st_size == 0:
        return alignments.limit(0)
    with allowlist.open(encoding="utf-8", newline="") as handle:
        names = tuple(line.removesuffix("\n").removesuffix("\r") for line in handle)
    allowed_names = (
        pl.Series(
            "reference_name",
            [name for name in names if name != ""],
            dtype=pl.String,
        )
        .to_frame()
        .lazy()
    )
    allowed_reads = (
        alignments.join(allowed_names, on="reference_name", how="semi")
        .select("read_key")
        .unique()
    )
    return alignments.join(allowed_reads, on="read_key", how="semi")


def write_versions(path: Path, process: str) -> None:
    """Write native dependency versions in nf-core versions-file form."""
    path.write_text(
        f'"{process}":\n'
        f'    polars: "{pl.__version__}"\n'
        f'    pysam: "{pysam.__version__}"\n'
        f'    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def ensure_payload_integrity(
    alignments: pl.LazyFrame,
    payloads: pl.LazyFrame,
) -> None:
    """Reject missing or ambiguous original payload associations."""
    duplicates = (
        payloads.group_by("read_key")
        .agg(pl.len().alias("records"))
        .filter(pl.col("records") > 1)
        .select("read_key")
        .limit(1)
        .collect()
    )
    if duplicates.height:
        message = (
            "Multiple original FASTQ records for retained read key "
            f"{duplicates.item()!r}."
        )
        raise SystemExit(message)
    missing = (
        alignments.join(payloads.select("read_key"), on="read_key", how="anti")
        .select(pl.len().alias("count"))
        .collect()
        .item()
    )
    if missing:
        message = f"{missing} reported BAM alignment(s) lack original FASTQ payload."
        raise SystemExit(message)


def ensure_reference_integrity(
    alignments: pl.LazyFrame,
    references: pl.LazyFrame,
) -> None:
    """Reject BAM target IDs absent from the selected FASTA association."""
    missing = (
        alignments.join(references, on="reference_id", how="anti")
        .select(pl.len().alias("count"))
        .collect()
        .item()
    )
    if missing:
        message = f"{missing} reported BAM alignment(s) lack a selected FASTA header."
        raise SystemExit(message)


def main() -> None:
    """Store a lookup-oriented classified-read table after BAM production."""
    args = parse_args()
    alignments_directory = args.output.with_name("classified-read-placement-batches")
    payload_directory = args.output.with_name("classified-read-payload-batches")
    references_path = args.output.with_name("classified-read-references.parquet")
    write_alignment_batches(args.bam, alignments_directory)
    write_references(args.fasta, references_path)
    alignment_metadata = pl.scan_parquet(alignments_directory / "*.parquet")
    references = pl.scan_parquet(references_path)
    ensure_reference_integrity(alignment_metadata, references)
    alignments = alignment_metadata.join(
        references,
        on="reference_id",
        how="inner",
    )
    retained_alignments = selected_alignments(alignments, args.allowlist)
    needed_reads = retained_alignments.select("read_key").unique().collect()
    write_matching_payload_batches(
        args.inputs,
        needed_reads,
        payload_directory,
    )
    payloads = (
        pl.scan_parquet(payload_directory / "*.parquet")
        if any(payload_directory.iterdir())
        else pl.LazyFrame(schema=PAYLOAD_SCHEMA)
    )
    ensure_payload_integrity(retained_alignments, payloads)
    retained_alignments.join(payloads, on="read_key", how="inner").with_columns(
        pl.lit(args.sample_id).alias("sample_id"),
        pl.lit(args.mapped_read_set).alias("mapped_read_set"),
        pl.lit(args.reference_specification).alias("reference_specification"),
    ).select(
        "sample_id",
        "mapped_read_set",
        "reference_specification",
        "read_key",
        "mapped_qname",
        "original_header",
        "sequence",
        "quality",
        "plus_line",
        "reference_id",
        "reference_name",
        "flag",
        "is_secondary",
        "is_supplementary",
        "is_primary",
        "strand",
        "start",
        "end",
        "cigar",
        "mapq",
        "alignment_score",
    ).sort(["reference_name", "read_key"]).sink_parquet(
        args.output,
        compression="zstd",
        statistics=True,
        row_group_size=BATCH_SIZE,
    )
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
