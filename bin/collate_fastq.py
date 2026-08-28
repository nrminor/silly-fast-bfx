#!/usr/bin/env python3

import argparse
import platform
import re
import shutil
from pathlib import Path


FASTQ_SUFFIXES = (".fastq", ".fq", ".fastq.gz", ".fq.gz")
COPY_BUFFER_BYTES = 8 * 1024 * 1024
CASAVA_NAME = re.compile(
    r"^(?P<prefix>.+)_L(?P<lane>\d{3})_R(?P<read>[12])_"
    r"(?P<chunk>\d{3})\.(?:fastq|fq)(?:\.gz)?$",
    re.IGNORECASE,
)
TERMINAL_READ_MARKER = re.compile(
    r"^(?P<prefix>.+)(?P<separator>[_.])(?P<r>R?)(?P<read>[12])(?P<chunk>_\d+)?$",
    re.IGNORECASE,
)
NATURAL_PART = re.compile(r"(\d+)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate and concatenate one grouped FASTQ input.")
    parser.add_argument("--sample-id", required=True)
    parser.add_argument("--r1-count", required=True, type=int)
    parser.add_argument("--single-end", action="store_true")
    parser.add_argument("--versions-output", required=True, type=Path)
    parser.add_argument("--process", required=True)
    return parser.parse_args()


def compression_kind(path: Path) -> str:
    return "gz" if path.name.lower().endswith(".gz") else "none"


def without_fastq_extension(path: Path) -> str:
    name = path.name
    if name.lower().endswith(".gz"):
        name = name[:-3]
    return name.rsplit(".", 1)[0]


def natural_key(value: str) -> tuple[object, ...]:
    return tuple(int(part) if part.isdigit() else part for part in NATURAL_PART.split(value))


def paired_key(path: Path) -> tuple[tuple[str, str, str, str], int]:
    if match := CASAVA_NAME.fullmatch(path.name):
        return (
            (
                match.group("prefix"),
                "casava",
                match.group("lane"),
                match.group("chunk"),
            ),
            int(match.group("read")),
        )

    if match := TERMINAL_READ_MARKER.fullmatch(without_fastq_extension(path)):
        chunk = match.group("chunk") or ""
        style = f"terminal:{match.group('separator')}{match.group('r').upper()}:{chunk}"
        return (
            (
                match.group("prefix"),
                style,
                "",
                chunk,
            ),
            int(match.group("read")),
        )

    raise SystemExit(f"Paired grouped FASTQ has no terminal mate key: {path.name}")


def paired_sort_key(key: tuple[str, str, str, str]) -> tuple[object, ...]:
    prefix, style, lane, chunk = key
    return natural_key(prefix), prefix, style, lane, chunk


def order_pairs(
    sample_id: str,
    reads: list[Path],
    r1_count: int,
) -> tuple[list[Path], list[Path]]:
    by_read: dict[int, dict[tuple[str, str, str, str], Path]] = {1: {}, 2: {}}
    for index, path in enumerate(reads):
        key, read = paired_key(path)
        expected_read = 1 if index < r1_count else 2
        if read != expected_read:
            raise SystemExit(
                f"Sample {sample_id} expected read {expected_read} in {path.name} but parsed read {read}",
            )
        if key in by_read[read]:
            raise SystemExit(f"Sample {sample_id} has duplicate read {read} key in {path.name}")
        by_read[read][key] = path

    if len(by_read[1]) != r1_count:
        raise SystemExit(
            f"Sample {sample_id} expected {r1_count} R1 files but parsed {len(by_read[1])}",
        )
    if by_read[1].keys() != by_read[2].keys():
        raise SystemExit(f"Sample {sample_id} has unequal paired FASTQ keys")

    ordered_keys = sorted(by_read[1], key=paired_sort_key)
    return (
        [by_read[1][key] for key in ordered_keys],
        [by_read[2][key] for key in ordered_keys],
    )


def staged_fastqs() -> list[Path]:
    def staged_index(path: Path) -> int:
        index = path.parent.name.removeprefix("reads")
        if not index.isdigit():
            raise SystemExit(f"Unexpected staged FASTQ directory: {path.parent.name}")
        return int(index)

    return sorted(
        [
            path
            for path in Path.cwd().glob("reads*/*")
            if path.is_file() and path.name.lower().endswith(FASTQ_SUFFIXES)
        ],
        key=staged_index,
    )


def concatenate(inputs: list[Path], output: Path) -> None:
    with output.open("wb") as destination:
        for path in inputs:
            with path.open("rb") as source:
                shutil.copyfileobj(source, destination, length=COPY_BUFFER_BYTES)


def write_versions(path: Path, process: str) -> None:
    path.write_text(
        f'"{process}":\n    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    reads = staged_fastqs()
    if args.r1_count < 1:
        raise SystemExit(f"Sample {args.sample_id} has no R1 FASTQ files")
    if args.single_end and len(reads) != args.r1_count:
        raise SystemExit(
            f"Sample {args.sample_id} expected {args.r1_count} R1 files but staged {len(reads)} FASTQs",
        )

    compressions = {compression_kind(path) for path in reads}
    if len(compressions) != 1:
        raise SystemExit(f"Sample {args.sample_id} mixes plain and gzip FASTQ files")

    extension = ".fastq.gz" if compressions == {"gz"} else ".fastq"
    if args.single_end:
        concatenate(sorted(reads, key=lambda path: path.name), Path(f"{args.sample_id}_R1{extension}"))
    else:
        r1, r2 = order_pairs(args.sample_id, reads, args.r1_count)
        concatenate(r1, Path(f"{args.sample_id}_R1{extension}"))
        concatenate(r2, Path(f"{args.sample_id}_R2{extension}"))
    write_versions(args.versions_output, args.process)


if __name__ == "__main__":
    main()
