#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "polars==1.43.2",
# ]
# ///

"""Convert cumulative sylph-tax canonical ranks into conserved Krona contributions."""

import argparse
import csv
import html
import math
import platform
from dataclasses import dataclass
from pathlib import Path

import polars as pl

RANK_PATH = r"^[dpcofgs]__[^|]+(?:\|[dpcofgs]__[^|]+)*$"


@dataclass(frozen=True)
class Args:
    """Paths and process identity for one taxonomy profile."""

    profile: Path
    output: Path
    versions: Path
    process: str


def parse_args() -> Args:
    """Parse one profile conversion request."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--versions", required=True, type=Path)
    parser.add_argument("--process", required=True)
    args = parser.parse_args()
    return Args(args.profile, args.output, args.versions, args.process)


def contributions(profile: Path) -> pl.DataFrame:
    """Subtract immediate children; retain positive direct mass at partial paths.

    Sylph-tax rows are cumulative. Each canonical parent can have a genuine
    unclassified remainder, so a deepest-row-only filter would lose it.
    Only the seven known rank prefixes are removed from display labels; no
    t__ path or reference-header content participates in the calculation.
    """
    source = pl.scan_csv(
        profile,
        separator="\t",
        comment_prefix="#",
        quote_char=None,
        infer_schema=False,
    )
    ranks = source.filter(pl.col("clade_name").str.contains(RANK_PATH)).select(
        pl.col("clade_name").alias("path"),
        pl.col("relative_abundance").cast(pl.Float64, strict=True).alias("abundance"),
    )
    if ranks.limit(1).collect().is_empty():
        return pl.DataFrame(schema={"path": pl.String, "residual": pl.Float64})
    duplicates = (
        ranks.group_by("path")
        .len()
        .filter(pl.col("len") > 1)
        .select("path")
        .limit(1)
        .collect()
    )
    if not duplicates.is_empty():
        message = f"Duplicate canonical taxonomy path: {duplicates['path'][0]}"
        raise ValueError(message)
    # Missing intermediate ranks do not make a descendant independent of its
    # nearest reported ancestor. At most seven canonical ranks can occur.
    candidates = pl.concat(
        [
            ranks.select(
                "path",
                pl.col("path")
                .str.split("|")
                .list.slice(
                    0,
                    pl.col("path").str.split("|").list.len() - distance,
                )
                .list.join("|")
                .alias("parent"),
                pl.lit(distance).alias("distance"),
            ).filter(pl.col("path") != pl.col("parent"))
            for distance in range(1, 7)
        ],
    )
    closest_parent = (
        candidates.join(ranks.select(pl.col("path").alias("parent")), on="parent")
        .group_by("path")
        .agg(pl.col("parent").sort_by("distance").first())
    )
    ranks = ranks.join(closest_parent, on="path", how="left")
    children = (
        ranks.filter(pl.col("parent").is_not_null())
        .group_by("parent")
        .agg(
            pl.col("abundance").sum().alias("children"),
        )
    )
    rows = (
        ranks.join(children, left_on="path", right_on="parent", how="left")
        .with_columns(
            (pl.col("abundance") - pl.col("children").fill_null(0.0)).alias("residual"),
        )
        .sort("path")
        .collect()
    )
    # Allow floating-point summation noise, never renormalize a real deficit.
    tolerance = 1e-7 * pl.max_horizontal(
        pl.lit(1.0),
        pl.col("abundance"),
        pl.col("children").fill_null(0.0),
    )
    invalid = rows.filter(
        pl.col("abundance").is_null()
        | ~pl.col("abundance").is_finite()
        | (pl.col("abundance") < 0)
        | (pl.col("residual") < -tolerance),
    )
    if not invalid.is_empty():
        message = f"Invalid or children-exceed-parent abundance: {invalid['path'][0]}"
        raise ValueError(message)
    return rows.filter(pl.col("residual") > 0).select("path", "residual")


def write_contributions(rows: pl.DataFrame, path: Path) -> None:
    """Write unheaded generic Krona input, escaping both XML and detail HTML.

    Krona XML-decodes its node name before inserting it into detail innerHTML.
    Escaping twice keeps literal markup as visible text at both boundaries.
    This occurs at the text-output boundary, after vectorized table operations.
    """
    if rows.is_empty() or math.fsum(rows["residual"]) <= 0:
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerows(
            (
                weight,
                *(html.escape(html.escape(rank[3:])) for rank in lineage.split("|")),
            )
            for lineage, weight in rows.iter_rows()
        )


def main() -> None:
    """Convert one Sylph taxonomy profile into optional Krona input."""
    args = parse_args()
    write_contributions(contributions(args.profile), args.output)
    args.versions.write_text(
        f'"{args.process}":\n'
        f'    polars: "{pl.__version__}"\n'
        f'    python: "{platform.python_version()}"\n',
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
