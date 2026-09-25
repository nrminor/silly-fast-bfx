#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = []
# ///

"""Download one HTTPS reference artifact."""

import argparse
import platform
import shutil
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Args:
    """Command-line configuration for one reference download."""

    url: str
    output: Path
    versions_output: Path
    process: str


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Download one HTTPS reference artifact."
    )
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    namespace = parser.parse_args()
    return Args(
        url=namespace.url,
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
    """Download the configured artifact after enforcing HTTPS throughout."""
    args = parse_args()
    if urllib.parse.urlsplit(args.url).scheme != "https":
        message = f"Reference URL must use HTTPS: {args.url}"
        raise SystemExit(message)

    partial = args.output.with_name(f".{args.output.name}.partial")
    try:
        # The initial URL is HTTPS-validated here, and redirects are checked below.
        with urllib.request.urlopen(args.url) as response, partial.open("wb") as output:  # noqa: S310
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                message = (
                    "Reference download redirected away from HTTPS: "
                    f"{response.geturl()}"
                )
                raise SystemExit(message)
            shutil.copyfileobj(response, output)
        partial.replace(args.output)
    finally:
        partial.unlink(missing_ok=True)

    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
