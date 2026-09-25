#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "biopython==1.87",
#   "polars==1.43.2",
# ]
# ///

"""Subset an explicit FASTA from exact full-header Sylph profile names."""

import argparse
import math
import platform
import sys
from collections.abc import Set as AbstractSet
from dataclasses import dataclass
from pathlib import Path

import polars as pl
from Bio import SeqIO

Bound = tuple[float | None, float | None]


@dataclass(frozen=True)
class Args:
    """Command-line configuration for reference subsetting."""

    profile: Path
    fasta: Path
    sequence_abundance: Bound
    adjusted_ani: Bound
    output_fasta: Path
    report: Path
    has_sequences_output: Path
    versions_output: Path
    process: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Subset an explicit FASTA from exact full-header Sylph profile names."
        ),
    )
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--fasta", required=True, type=Path)
    parser.add_argument("--sequence-abundance-min", type=float)
    parser.add_argument("--sequence-abundance-max", type=float)
    parser.add_argument("--adjusted-ani-min", type=float)
    parser.add_argument("--adjusted-ani-max", type=float)
    parser.add_argument("--output-fasta", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--has-sequences-output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        profile=namespace.profile,
        fasta=namespace.fasta,
        sequence_abundance=(
            namespace.sequence_abundance_min,
            namespace.sequence_abundance_max,
        ),
        adjusted_ani=(namespace.adjusted_ani_min, namespace.adjusted_ani_max),
        output_fasta=namespace.output_fasta,
        report=namespace.report,
        has_sequences_output=namespace.has_sequences_output,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def active_bounds(args: Args) -> dict[str, Bound]:
    """Return configured inclusive bounds after rejecting impossible ranges."""
    bounds = {
        "Sequence_abundance": args.sequence_abundance,
        "Adjusted_ANI": args.adjusted_ani,
    }
    nonfinite = [
        column
        for column, bound in bounds.items()
        if any(value is not None and not math.isfinite(value) for value in bound)
    ]
    if nonfinite:
        message = f"Configured bounds must be finite for: {', '.join(nonfinite)}"
        raise SystemExit(message)
    invalid = [
        column
        for column, (minimum, maximum) in bounds.items()
        if minimum is not None and maximum is not None and minimum > maximum
    ]
    if invalid:
        message = f"Minimum exceeds maximum for: {', '.join(invalid)}"
        raise SystemExit(message)
    return bounds


def numeric_bound_conditions(column: str, bound: Bound) -> tuple[pl.Expr, ...]:
    """Return eligibility conditions for the configured bounds on one column."""
    minimum, maximum = bound
    numeric_column = pl.col(column).cast(pl.Float64, strict=False)
    is_valid = numeric_column.is_not_null() & numeric_column.is_finite()
    return (
        *((is_valid & (numeric_column >= minimum),) if minimum is not None else ()),
        *((is_valid & (numeric_column <= maximum),) if maximum is not None else ()),
    )


def select_profile_rows(profile: Path, bounds: dict[str, Bound]) -> pl.LazyFrame:
    """Lazily classify profile rows as filtered out or candidate reference names."""
    profile_rows = pl.scan_csv(profile, separator="\t")
    columns = profile_rows.collect_schema().names()
    active_columns = [
        column
        for column, bound in bounds.items()
        if any(value is not None for value in bound)
    ]
    required = ["Contig_name", *active_columns]
    missing = [column for column in required if column not in columns]
    if missing:
        message = f"Sylph profile is missing required column(s): {', '.join(missing)}"
        raise SystemExit(message)

    conditions = tuple(
        condition
        for column, bound in bounds.items()
        for condition in numeric_bound_conditions(column, bound)
    )
    eligible = pl.lit(value=True) if not conditions else pl.all_horizontal(conditions)
    return profile_rows.with_columns(
        pl.when(eligible)
        .then(pl.lit("candidate"))
        .otherwise(pl.lit("filtered_out"))
        .alias("status"),
    ).select("Contig_name", "status")


def candidate_names(selection: pl.LazyFrame) -> AbstractSet[str]:
    """Return candidate names after rejecting null values before matching."""
    candidates = (
        selection.filter(pl.col("status") == "candidate")
        .select(pl.col("Contig_name").cast(pl.String).unique())
        .collect()
        .get_column("Contig_name")
    )
    if candidates.null_count():
        message = "Candidate Sylph Contig_name values must not be null"
        raise SystemExit(message)
    return frozenset(candidates.to_list())


def write_selected_records(
    fasta: Path,
    names: AbstractSet[str],
    output_fasta: Path,
) -> AbstractSet[str]:
    """Stream matching records and retain only metadata needed for diagnostics."""
    seen_headers: set[str] = set()
    duplicate_headers: set[str] = set()
    seen_ids: set[str] = set()
    duplicate_ids: set[str] = set()
    resolved_names: set[str] = set()
    with output_fasta.open("w", encoding="utf-8") as output:
        for record in SeqIO.parse(fasta, "fasta"):
            if record.description not in names:
                continue
            if record.description in seen_headers:
                duplicate_headers.add(record.description)
            seen_headers.add(record.description)
            if record.id in seen_ids:
                duplicate_ids.add(record.id)
            seen_ids.add(record.id)
            resolved_names.add(record.description)
            SeqIO.write(record, output, "fasta")
    if duplicate_headers:
        message = (
            "Selected FASTA has duplicate full header(s): "
            f"{', '.join(sorted(duplicate_headers))}"
        )
        raise SystemExit(message)
    if duplicate_ids:
        message = (
            "Selected FASTA has duplicate sequence ID(s): "
            f"{', '.join(sorted(duplicate_ids))}"
        )
        raise SystemExit(message)
    return frozenset(resolved_names)


def selection_report(
    selection: pl.LazyFrame,
    resolved_names: AbstractSet[str],
) -> pl.LazyFrame:
    """Mark candidate names without collecting profile rows."""
    return selection.with_columns(
        pl.when(pl.col("status") == "candidate")
        .then(
            pl.when(pl.col("Contig_name").is_in(resolved_names))
            .then(pl.lit("resolved"))
            .otherwise(pl.lit("unresolved")),
        )
        .otherwise(pl.col("status"))
        .alias("status"),
    ).select("Contig_name", "status")


def write_versions(path: Path, process: str) -> None:
    """Write the Python version in nf-core versions-file form."""
    path.write_text(
        f'"{process}":\n    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    """Select records, report every profile row, and signal meaningful output."""
    args = parse_args()
    bounds = active_bounds(args)
    selection = select_profile_rows(args.profile, bounds)
    names = candidate_names(selection)
    resolved_names = write_selected_records(args.fasta, names, args.output_fasta)
    selection_report(selection, resolved_names).sink_csv(args.report, separator="\t")
    unresolved = names - resolved_names
    if resolved_names and unresolved:
        message = (
            "Selected Sylph names are only partially resolved in FASTA: "
            f"{', '.join(sorted(unresolved))}"
        )
        raise SystemExit(message)
    if names and not resolved_names:
        sys.stdout.write(
            "WARN: No selected Sylph Contig_name values matched "
            "the explicit mapping FASTA.\n",
        )

    args.has_sequences_output.write_text(
        f"{bool(resolved_names)}\n".lower(),
        encoding="utf-8",
    )
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
