#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Report whether a Deacon summary contains reads.")
    parser.add_argument("--summary", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        summary = json.loads(args.summary.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Cannot read Deacon summary {args.summary}: {error}") from error

    seqs_out = summary.get("seqs_out") if isinstance(summary, dict) else None
    if type(seqs_out) is not int or seqs_out < 0:
        raise SystemExit(
            f"Deacon summary {args.summary} must contain a nonnegative integer seqs_out",
        )

    print("true" if seqs_out > 0 else "false")


if __name__ == "__main__":
    main()
