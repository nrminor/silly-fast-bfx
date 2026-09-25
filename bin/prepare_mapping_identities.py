#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "polars==1.43.2",
#   "pysam==0.23.3",
# ]
# ///

"""Validate mapper QNAME identities without materializing read payloads."""

import argparse
import platform
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import polars as pl
import pysam

ERROR_NAMES_LIMIT = 20
PAIR_RECORDS = 2


@dataclass(frozen=True)
class Args:
    """Command-line configuration for mapping identity preparation."""

    inputs: tuple[Path, ...]
    collisions: Path
    count_output: Path
    has_reads_output: Path
    versions_output: Path
    process: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", action="append", required=True, type=Path)
    parser.add_argument("--collisions", required=True, type=Path)
    parser.add_argument("--count-output", required=True, type=Path)
    parser.add_argument("--has-reads-output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        inputs=tuple(namespace.input),
        collisions=namespace.collisions,
        count_output=namespace.count_output,
        has_reads_output=namespace.has_reads_output,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def explicit_mate(name: str, comment: str) -> str | None:
    """Return only mate information explicitly represented by the FASTQ header."""
    if name.endswith(("/1", "/2")):
        return name[-1]
    return comment[0] if comment.startswith(("1:", "2:")) else None


def write_name_metadata(inputs: Sequence[Path], output: Path) -> int:
    """Stream mapper-visible names and explicit mate facts into a compact TSV."""
    ordinal = 0
    with output.open("w", encoding="utf-8") as handle:
        handle.write("ordinal\tqname\tmate\n")
        for path in inputs:
            with pysam.FastxFile(str(path)) as records:
                for record in records:
                    name = record.name or ""
                    mate = explicit_mate(name, record.comment or "")
                    handle.write(f"{ordinal}\t{name}\t{mate or ''}\n")
                    ordinal += 1
    return ordinal


def scan_names(path: Path) -> pl.LazyFrame:
    """Lazily scan compact per-record metadata, never sequence payload."""
    return pl.scan_csv(
        path,
        separator="\t",
        schema={"ordinal": pl.Int64, "qname": pl.String, "mate": pl.String},
        null_values="",
    )


def name_statistics(names: pl.LazyFrame) -> pl.LazyFrame:
    """Derive collision facts in Polars' native grouped execution."""
    return names.group_by("qname").agg(
        pl.len().alias("occurrences"),
        pl.col("mate").drop_nulls().n_unique().alias("mate_count"),
        pl.col("mate").drop_nulls().min().alias("first_mate"),
        pl.col("mate").drop_nulls().max().alias("last_mate"),
    )


def diagnostic_names(names: pl.LazyFrame) -> list[str]:
    """Collect only a bounded set of names for an error message."""
    return names.head(ERROR_NAMES_LIMIT).collect().get_column("qname").to_list()


def valid_mate_collision() -> pl.Expr:
    """Define the only collision that can be disambiguated without inference."""
    return (
        (pl.col("occurrences") == PAIR_RECORDS)
        & (pl.col("mate_count") == PAIR_RECORDS)
        & (pl.col("first_mate") == "1")
        & (pl.col("last_mate") == "2")
    )


def validate_collisions(names: pl.LazyFrame, statistics: pl.LazyFrame) -> None:
    """Reject ambiguous mapper names and suffixes colliding with existing names."""
    unresolved = statistics.filter(
        (pl.col("occurrences") > 1) & ~valid_mate_collision(),
    )
    if collisions := diagnostic_names(unresolved):
        message = "Unresolved mapping QNAME collision(s): " + ", ".join(collisions)
        raise SystemExit(message)

    renamed = (
        names.join(
            statistics.filter(pl.col("occurrences") > 1).select("qname"),
            on="qname",
            how="inner",
        )
        .select(
            pl.concat_str([pl.col("qname"), pl.lit("/"), pl.col("mate")]).alias(
                "qname",
            ),
        )
        .unique()
    )
    existing = names.select("qname").unique()
    suffix_collisions = renamed.join(existing, on="qname", how="semi")
    if collisions := diagnostic_names(suffix_collisions):
        message = "Mate suffixes introduce mapping QNAME collision(s): " + ", ".join(
            collisions,
        )
        raise SystemExit(message)


def write_collision_names(
    names: pl.LazyFrame,
    statistics: pl.LazyFrame,
    output: Path,
) -> None:
    """Write only necessary ordered mapper-name substitutions for the second pass."""
    (
        names.join(
            statistics.filter(pl.col("occurrences") > 1).select("qname"),
            on="qname",
            how="inner",
        )
        .select(
            "ordinal",
            pl.concat_str([pl.col("qname"), pl.lit("/"), pl.col("mate")]).alias(
                "mapped_name",
            ),
        )
        .sort("ordinal")
        .sink_csv(output, separator="\t")
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
    """Validate identities and create a metadata-only collision stream."""
    args = parse_args()
    names_path = args.collisions.with_name("mapping-names.tsv")
    count = write_name_metadata(args.inputs, names_path)
    names = scan_names(names_path)
    statistics = name_statistics(names)
    validate_collisions(names, statistics)
    write_collision_names(names, statistics, args.collisions)
    args.count_output.write_text(f"{count}\n", encoding="utf-8")
    args.has_reads_output.write_text(f"{bool(count)}\n".lower(), encoding="utf-8")
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
