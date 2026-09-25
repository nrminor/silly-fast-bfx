#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = []
# ///

"""Write an ordered reference checksum manifest."""

import argparse
import platform
import re
from dataclasses import dataclass
from pathlib import Path

SHA256 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class Args:
    """Command-line configuration for checksum manifest writing."""

    entries: tuple[tuple[str, str], ...]
    output: Path
    versions_output: Path
    process: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Write an ordered reference checksum manifest.",
    )
    parser.add_argument(
        "--entry",
        action="append",
        nargs=2,
        metavar=("SHA256", "BASENAME"),
        default=[],
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        entries=tuple((digest, basename) for digest, basename in namespace.entry),
        output=namespace.output,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def checksum_line(digest: str, basename: str) -> str:
    """Validate one manifest entry and render its line."""
    if not SHA256.fullmatch(digest):
        message = f"Invalid observed SHA-256 for {basename}: {digest}"
        raise SystemExit(message)
    if not basename or any(character in basename for character in "\n\r/\\"):
        message = f"Invalid logical basename: {basename!r}"
        raise SystemExit(message)
    return f"{digest}  {basename}\n"


def write_versions(path: Path, process: str) -> None:
    """Write the Python version for an nf-core process versions file."""
    path.write_text(
        f'"{process}":\n    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    """Validate entries and write an ordered checksum manifest."""
    args = parse_args()

    args.output.write_text(
        "".join(checksum_line(*entry) for entry in args.entries), encoding="utf-8"
    )
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
