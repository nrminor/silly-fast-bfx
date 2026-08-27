#!/usr/bin/env python3

import argparse
import hashlib
import platform
import re
from pathlib import Path


SHA256 = re.compile(r"^[0-9a-fA-F]{64}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record and optionally verify a reference SHA-256.")
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--location", required=True)
    parser.add_argument("--expected", action="append", default=[])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    return parser.parse_args()


def write_versions(path: Path, process: str) -> None:
    path.write_text(
        f'"{process}":\n    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    invalid = [expected for expected in args.expected if not SHA256.fullmatch(expected)]
    if invalid:
        raise SystemExit(f"Invalid expected SHA-256 for {args.location}: {', '.join(invalid)}")

    with args.artifact.open("rb") as artifact:
        observed = hashlib.file_digest(artifact, "sha256").hexdigest()

    expected = sorted({digest.lower() for digest in args.expected})
    mismatches = [digest for digest in expected if digest != observed]
    if mismatches:
        raise SystemExit(
            f"SHA-256 mismatch for {args.location}: "
            f"expected {', '.join(mismatches)}, observed {observed}"
        )

    args.output.write_text(f"{observed}\n", encoding="utf-8")
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
