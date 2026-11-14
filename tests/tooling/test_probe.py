import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import ahk
import probe


class ProbeWrapperTests(unittest.TestCase):
    def test_snippet_gets_prelude_includes_and_exit(self):
        text = probe.wrapper(None, "x := 1", [Path("lib.ahk").resolve()])
        self.assertTrue(text.startswith("#Requires AutoHotkey v2.0\n#Warn All, StdOut\n"))
        self.assertIn("OnError(", text)
        self.assertIn("#Include " + ahk.to_ahk_path(Path("lib.ahk")), text)
        self.assertTrue(text.endswith("x := 1\nExitApp(0)\n"))

    def test_script_is_included_after_prelude_without_forced_exit(self):
        text = probe.wrapper(Path("try.ahk").resolve(), "", [])
        self.assertTrue(text.rstrip().endswith("#Include " + ahk.to_ahk_path(Path("try.ahk"))))
        self.assertNotIn("ExitApp(0)", text)

    def test_script_and_code_are_exclusive(self):
        with self.assertRaises(SystemExit):
            probe.main(["try.ahk", "--code", "x := 1"])
        with self.assertRaises(SystemExit):
            probe.main([])


class RunDialogTests(unittest.TestCase):
    def test_dialog_ends_the_run_and_is_reported(self):
        proc = unittest.mock.MagicMock(pid=42, returncode=1)
        proc.wait.side_effect = [subprocess.TimeoutExpired("x", 0.2), None]
        with patch.object(ahk, "IS_WINDOWS", True), \
                patch.object(ahk, "dialog_texts", return_value=["t.ahk: Error: boom"]):
            code, dialogs, timed_out = ahk._wait(proc, 30)
        proc.kill.assert_called_once()
        self.assertEqual(["t.ahk: Error: boom"], dialogs)
        self.assertFalse(timed_out)

    def test_timeout_without_dialog(self):
        proc = unittest.mock.MagicMock(pid=42, returncode=1)
        proc.wait.side_effect = [subprocess.TimeoutExpired("x", 0.2), None]
        with patch.object(ahk, "IS_WINDOWS", False):
            code, dialogs, timed_out = ahk._wait(proc, 0)
        proc.kill.assert_called_once()
        self.assertEqual([], dialogs)
        self.assertTrue(timed_out)

    def test_normal_exit(self):
        proc = unittest.mock.MagicMock(pid=42)
        proc.wait.return_value = 0
        self.assertEqual((0, [], False), ahk._wait(proc, 30))
        proc.kill.assert_not_called()

    @unittest.skipUnless(ahk.IS_WINDOWS and Path(ahk.ahk_exe()).is_file(), "needs AutoHotkey on Windows")
    def test_real_warning_dialog_is_captured(self):
        with tempfile.TemporaryDirectory() as d:
            script = Path(d) / "warn.ahk"
            script.write_text("#Requires AutoHotkey v2.0\nx := y + 1\nExitApp\n", encoding="utf-8")
            r = ahk.run(script, timeout=30)
        self.assertEqual(ahk.DIALOG_EXIT, r.code)
        self.assertIn("dialog: warn.ahk:", r.out)
        self.assertIn("Specifically: y", r.out)


if __name__ == "__main__":
    unittest.main()
