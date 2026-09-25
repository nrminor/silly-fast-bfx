#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "pysam==0.23.3",
# ]
# ///

"""Stream original FASTQ records to a mapper with validated name substitutions."""

import argparse
import csv
import sys
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path

import pysam


@dataclass(frozen=True)
class Args:
    """Command-line configuration for mapper read streaming."""

    inputs: tuple[Path, ...]
    collisions: Path


@dataclass(frozen=True)
class Collision:
    """One ordinally-addressed mapper-name substitution."""

    ordinal: int
    mapped_name: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", action="append", required=True, type=Path)
    parser.add_argument("--collisions", required=True, type=Path)
    namespace = parser.parse_args()
    return Args(inputs=tuple(namespace.input), collisions=namespace.collisions)


def read_collisions(path: Path) -> Iterator[Collision]:
    """Read the ordered, metadata-only collision stream."""
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            yield Collision(ordinal=int(row["ordinal"]), mapped_name=row["mapped_name"])


def write_fastq_record(name: str, sequence: str, quality: str) -> None:
    """Write the mapper-only FASTQ representation without storing it on disk."""
    sys.stdout.write(f"@{name}\n{sequence}\n+\n{quality}\n")


def stream_records(inputs: Sequence[Path], collisions: Iterator[Collision]) -> None:
    """Make one bounded pass through original FASTQs and ordered substitutions."""
    ordinal = 0
    collision = next(collisions, None)
    for path in inputs:
        with pysam.FastxFile(str(path)) as records:
            for record in records:
                mapped_name = record.name or ""
                if collision is not None and collision.ordinal == ordinal:
                    mapped_name = collision.mapped_name
                    collision = next(collisions, None)
                write_fastq_record(
                    mapped_name,
                    record.sequence or "",
                    record.quality or "",
                )
                ordinal += 1
    if collision is not None:
        message = "Collision metadata does not match the streamed FASTQ records"
        raise SystemExit(message)


def main() -> None:
    """Stream original reads into minimap2 without materializing another FASTQ."""
    args = parse_args()
    stream_records(args.inputs, read_collisions(args.collisions))


if __name__ == "__main__":
    main()
