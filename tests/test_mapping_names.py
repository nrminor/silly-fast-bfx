"""Focused shared mapper/store naming checks."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import polars as pl
from store_classified_reads import (
    ensure_payload_integrity,
    payload_rows,
    write_matching_payload_batches,
)
from stream_mapping_reads import mapper_name, stream_records


class MappingNamesTest(unittest.TestCase):
    """Check mapper names and retained original payload associations."""

    def test_names(self) -> None:
        """Preserve ordinary and existing mate names; honor explicit comments."""
        self.assertEqual(mapper_name("ordinary comment"), "ordinary")
        self.assertEqual(mapper_name("already/1 2:N:0:1"), "already/1")
        self.assertEqual(mapper_name("already/2 1:N:0:1"), "already/2")
        self.assertEqual(mapper_name("alone\t2:N:0:1"), "alone/2")
        self.assertEqual(mapper_name("alone\t1:N:0:1"), "alone/1")
        self.assertEqual(mapper_name("alone not1:N:0:1"), "alone")

    def test_store_uses_same_name_and_preserves_header(self) -> None:
        """Keep the FASTQ header intact after computing its mapper name."""
        reads = Path(__file__).parent / "data/mapping/lanes/r2/reads.fastq"
        key, header, *_ = next(payload_rows((reads,)))
        self.assertEqual(key, mapper_name(header))
        self.assertEqual(key, "same/2")
        self.assertEqual(header, "same 2:N:0:1")

    def test_stream_and_store_agree_on_tab_separated_single_mate(self) -> None:
        """Stream and store a lone explicit mate with a tab-separated comment."""
        with tempfile.TemporaryDirectory() as temporary:
            reads = Path(temporary) / "one.fastq"
            reads.write_text("@one\t2:N:0:1\nACGT\n+original\nIIII\n", encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                stream_records((reads,))
            key, header, sequence, quality, plus_line = next(payload_rows((reads,)))
            self.assertEqual(output.getvalue(), "@one/2\nACGT\n+\nIIII\n")
            self.assertEqual(
                (key, header, sequence, quality, plus_line),
                ("one/2", "one\t2:N:0:1", "ACGT", "IIII", "original"),
            )

    def test_duplicate_retained_payload_across_batches_fails(self) -> None:
        """Reject two original records for a retained key across batches."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first, second = root / "first.fastq", root / "second.fastq"
            for path in (first, second):
                path.write_text("@duplicate\nACGT\n+\nIIII\n", encoding="utf-8")
            directory = root / "batches"
            needed = pl.DataFrame({"read_key": ["duplicate"]})
            with patch("store_classified_reads.BATCH_SIZE", 1):
                write_matching_payload_batches((first, second), needed, directory)
            self.assertEqual(len(list(directory.glob("*.parquet"))), 2)
            with self.assertRaisesRegex(SystemExit, "Multiple original FASTQ records"):
                ensure_payload_integrity(
                    pl.LazyFrame({"read_key": ["duplicate"]}),
                    pl.scan_parquet(directory / "*.parquet"),
                )


if __name__ == "__main__":
    unittest.main()
