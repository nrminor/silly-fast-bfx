#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "pysam==0.23.3",
# ]
# ///

"""Stream original FASTQ records to minimap2 with explicit mate names."""

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import pysam


@dataclass(frozen=True)
class Args:
    """Command-line configuration for mapper read streaming."""

    inputs: tuple[Path, ...]


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", action="append", required=True, type=Path)
    namespace = parser.parse_args()
    return Args(inputs=tuple(namespace.input))


def mapper_name(header: str) -> str:
    """Suffix only unsuffixed names with an explicit 1:/2: header comment."""
    parts = header.split(maxsplit=1)
    if not parts:
        message = "FASTQ record has an empty header"
        raise ValueError(message)
    name = parts[0]
    if (
        not name.endswith(("/1", "/2"))
        and len(parts) > 1
        and parts[1].startswith(("1:", "2:"))
    ):
        return f"{name}/{parts[1][0]}"
    return name


def write_fastq_record(name: str, sequence: str, quality: str) -> None:
    """Write the mapper-only FASTQ representation without storing it on disk."""
    sys.stdout.write(f"@{name}\n{sequence}\n+\n{quality}\n")


def stream_records(inputs: Sequence[Path]) -> None:
    """Make one bounded pass through original FASTQs."""
    for path in inputs:
        with pysam.FastxFile(str(path)) as records:
            for record in records:
                header = (record.name or "") + (
                    f" {record.comment}" if record.comment else ""
                )
                write_fastq_record(
                    mapper_name(header),
                    record.sequence or "",
                    record.quality or "",
                )


def main() -> None:
    """Stream original reads into minimap2 without materializing another FASTQ."""
    args = parse_args()
    stream_records(args.inputs)


if __name__ == "__main__":
    main()
