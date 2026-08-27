#!/usr/bin/env python3

import argparse
import platform
import shutil
import urllib.parse
import urllib.request
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download one HTTPS reference artifact.")
    parser.add_argument("--url", required=True)
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
    if urllib.parse.urlsplit(args.url).scheme != "https":
        raise SystemExit(f"Reference URL must use HTTPS: {args.url}")

    partial = args.output.with_name(f".{args.output.name}.partial")
    try:
        with urllib.request.urlopen(args.url) as response, partial.open("wb") as output:
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                raise SystemExit(f"Reference download redirected away from HTTPS: {response.geturl()}")
            shutil.copyfileobj(response, output)
        partial.replace(args.output)
    finally:
        partial.unlink(missing_ok=True)

    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
