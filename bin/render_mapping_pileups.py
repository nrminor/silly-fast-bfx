#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# ///

"""Render one self-contained Alignoth HTML pileup per covered reference."""

import argparse
import csv
import subprocess
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote


@dataclass(frozen=True)
class Args:
    """Command-line configuration for Alignoth pileup rendering."""

    bam: Path
    fasta: Path
    coverage: Path
    output: Path
    max_read_depth: int


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bam", required=True, type=Path)
    parser.add_argument("--fasta", required=True, type=Path)
    parser.add_argument("--coverage", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--max-read-depth", required=True, type=int)
    namespace = parser.parse_args()
    return Args(
        bam=namespace.bam,
        fasta=namespace.fasta,
        coverage=namespace.coverage,
        output=namespace.output,
        max_read_depth=namespace.max_read_depth,
    )


def covered_references(path: Path) -> tuple[tuple[str, int], ...]:
    """Read compact coverage rows and retain only references with mapped support."""
    with path.open(encoding="utf-8", newline="") as handle:
        rows = csv.DictReader(handle, delimiter="\t")
        return tuple(
            (row["reference_id"], int(row["reference_length"]))
            for row in rows
            if int(row["distinct_read_count"]) > 0
        )


def render_reference(args: Args, reference_id: str, reference_length: int) -> None:
    """Run Alignoth with argv execution so reference IDs never enter a shell command."""
    output = args.output / f"{quote(reference_id, safe='')}.alignoth.html"
    command = [
        "alignoth",
        "--bam-path",
        str(args.bam),
        "--reference",
        str(args.fasta),
        "--region",
        f"{reference_id}:1-{reference_length}",
        "--max-read-depth",
        str(args.max_read_depth),
        "--max-width",
        "1024",
        "--mismatch-display-min-percent",
        "1.0",
        "--html",
    ]
    with output.open("w", encoding="utf-8") as handle:
        subprocess.run(command, check=True, stdout=handle)  # noqa: S603


def main() -> None:
    """Render covered references while leaving quantitative evidence untouched."""
    args = parse_args()
    args.output.mkdir()
    for reference_id, reference_length in covered_references(args.coverage):
        render_reference(args, reference_id, reference_length)


if __name__ == "__main__":
    main()
