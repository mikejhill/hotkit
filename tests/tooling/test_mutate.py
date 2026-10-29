import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import ahk
import mutate


class MutationEvidenceTests(unittest.TestCase):
    def exercise(self, outcomes, baseline=None, extra=()):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            source.mkdir()
            report = Path(temp) / "result.json"
            mutants = [mutate.Mutant("logic.ahk", i + 1, "eq->ne", "a = b", "a != b")
                       for i in range(len(outcomes))]
            good = ahk.Result(0, "TAP version 13\n# 2/2 passed")
            with patch.object(mutate, "REPO", source), patch.object(mutate, "generate", return_value=mutants), \
                    patch.object(ahk, "run", return_value=baseline or good), \
                    patch.object(mutate, "run_mutant", side_effect=lambda m, *_: outcomes[m.line - 1]), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = mutate.main(["--jobs", "1", "--max", "0", "--json-report", str(report), *extra])
            return code, json.loads(report.read_text())

    def test_runner_error_is_not_killed(self):
        code, report = self.exercise(["error", "killed"])
        self.assertEqual(code, 2)
        self.assertEqual(report["status"], "incomplete")
        self.assertEqual(report["errors"], 1)
        self.assertEqual(report["killed"], 1)

    def test_complete_findings_and_healthy(self):
        code, report = self.exercise(["survived", "killed"])
        self.assertEqual((code, report["status"], report["score"]), (1, "findings", 50))
        code, report = self.exercise(["killed"])
        self.assertEqual((code, report["status"], report["full_scope"]), (0, "healthy", True))

    def test_partial_file_scope_cannot_claim_full_recovery(self):
        _, report = self.exercise(["killed"], extra=["--file", "logic.ahk"])
        self.assertFalse(report["full_scope"])

    def test_survivors_at_or_above_threshold_are_healthy(self):
        for threshold in (90, 80):
            with self.subTest(threshold=threshold):
                code, report = self.exercise(["killed"] * 9 + ["survived"],
                                             extra=["--threshold", str(threshold)])
                self.assertEqual((code, report["status"], report["score"]), (0, "healthy", 90))
                self.assertEqual(report["survived"], 1)

    def test_baseline_missing_or_incomplete_tap_is_not_success(self):
        for output in ["", "TAP version 13\n# 0/0 passed", "TAP version 13\n# 1/2 passed"]:
            with self.subTest(output=output):
                code, report = self.exercise(["killed"], baseline=ahk.Result(0, output))
                self.assertEqual((code, report["status"]), (2, "incomplete"))

    def test_no_valid_mutants_is_incomplete(self):
        code, report = self.exercise(["invalid"])
        self.assertEqual((code, report["status"]), (2, "incomplete"))

    def test_timeout_is_runner_error_and_source_is_restored(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "logic.ahk"
            source.write_text("a = b\n")
            mutant = mutate.Mutant("logic.ahk", 1, "eq->ne", "a = b", "a != b")
            with patch.object(ahk, "run", return_value=ahk.Result(124, "", timed_out=True)):
                self.assertEqual(mutate.run_mutant(mutant, Path(temp), 1), "error")
            self.assertEqual(source.read_text(), "a = b\n")


if __name__ == "__main__":
    unittest.main()
