#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = []
# ///

"""Record and optionally verify a reference SHA-256."""

import argparse
import hashlib
import platform
import re
from dataclasses import dataclass
from pathlib import Path

SHA256 = re.compile(r"^[0-9a-fA-F]{64}$")


@dataclass(frozen=True)
class Args:
    """Command-line configuration for reference verification."""

    artifact: Path
    location: str
    expected: tuple[str, ...]
    output: Path
    versions_output: Path
    process: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Record and optionally verify a reference SHA-256.",
    )
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--location", required=True)
    parser.add_argument("--expected", action="append", default=[])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        artifact=namespace.artifact,
        location=namespace.location,
        expected=tuple(namespace.expected),
        output=namespace.output,
        versions_output=namespace.versions_output,
        process=namespace.process,
    )


def write_versions(path: Path, process: str) -> None:
    """Write the Python version for an nf-core process versions file."""
    path.write_text(
        f'"{process}":\n    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    """Verify the artifact digest and write its observed value."""
    args = parse_args()
    invalid = [expected for expected in args.expected if not SHA256.fullmatch(expected)]
    if invalid:
        message = f"Invalid expected SHA-256 for {args.location}: {', '.join(invalid)}"
        raise SystemExit(message)

    with args.artifact.open("rb") as artifact:
        observed = hashlib.file_digest(artifact, "sha256").hexdigest()

    expected = sorted({digest.lower() for digest in args.expected})
    mismatches = [digest for digest in expected if digest != observed]
    if mismatches:
        message = (
            f"SHA-256 mismatch for {args.location}: "
            f"expected {', '.join(mismatches)}, observed {observed}"
        )
        raise SystemExit(message)

    args.output.write_text(f"{observed}\n", encoding="utf-8")
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
