#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = []
# ///

"""Report whether a Deacon summary contains output reads."""

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Args:
    """Command-line configuration for Deacon summary checking."""

    summary: Path


def parse_args() -> Args:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Report whether a Deacon summary contains reads.",
    )
    parser.add_argument("--summary", required=True, type=Path)
    namespace = parser.parse_args()
    return Args(summary=namespace.summary)


def main() -> None:
    """Print whether the Deacon summary has output reads."""
    args = parse_args()
    try:
        summary = json.loads(args.summary.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        message = f"Cannot read Deacon summary {args.summary}: {error}"
        raise SystemExit(message) from error

    seqs_out = summary.get("seqs_out") if isinstance(summary, dict) else None
    if type(seqs_out) is not int or seqs_out < 0:
        message = (
            f"Deacon summary {args.summary} must contain a nonnegative integer seqs_out"
        )
        raise SystemExit(message)

    sys.stdout.write("true\n" if seqs_out > 0 else "false\n")


if __name__ == "__main__":
    main()
