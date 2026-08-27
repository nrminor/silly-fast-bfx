#!/usr/bin/env python3

import argparse
import platform
import re
from pathlib import Path


SHA256 = re.compile(r"^[0-9a-f]{64}$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write an ordered reference checksum manifest.")
    parser.add_argument("--entry", action="append", nargs=2, metavar=("SHA256", "BASENAME"), default=[])
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
    lines: list[str] = []
    for digest, basename in args.entry:
        if not SHA256.fullmatch(digest):
            raise SystemExit(f"Invalid observed SHA-256 for {basename}: {digest}")
        if not basename or "\n" in basename or "\r" in basename or "/" in basename or "\\" in basename:
            raise SystemExit(f"Invalid logical basename: {basename!r}")
        lines.append(f"{digest}  {basename}\n")

    args.output.write_text("".join(lines), encoding="utf-8")
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
