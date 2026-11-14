import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import release
from release import ReleaseError

APP = 'class App {\n    static Version := "1.7.0"\n}\n'
CHANGELOG = """# Changelog

## [Unreleased]

### Fixed
- A fix.

## [1.7.0] - 2026-11-14

### Added
- A feature.

## [1.6.0] - 2026-11-13

### Added
- Older.
"""


class BumpTests(unittest.TestCase):
    def test_bump_resets_lower_parts(self):
        self.assertEqual(release.bump((1, 7, 3), "major"), (2, 0, 0))
        self.assertEqual(release.bump((1, 7, 3), "minor"), (1, 8, 0))
        self.assertEqual(release.bump((1, 7, 3), "patch"), (1, 7, 4))

    def test_infer_bump_from_subsections(self):
        self.assertEqual(release.infer_bump("### Fixed\n- x"), "patch")
        self.assertEqual(release.infer_bump("### Security\n- x"), "patch")
        self.assertEqual(release.infer_bump("### Fixed\n- x\n### Changed\n- y"), "minor")
        self.assertEqual(release.infer_bump("### Added\n- x"), "minor")
        self.assertEqual(release.infer_bump("### Removed\n- x"), "major")
        self.assertEqual(release.infer_bump("### Changed\n- **Breaking:** renamed x"), "major")

    def test_infer_bump_needs_a_known_subsection(self):
        with self.assertRaises(ReleaseError):
            release.infer_bump("- loose entry")


class TextTests(unittest.TestCase):
    def test_app_version_roundtrip(self):
        self.assertEqual(release.app_version(APP), "1.7.0")
        self.assertEqual(release.app_version(release.set_app_version(APP, "1.8.0")), "1.8.0")

    def test_section_extracts_body(self):
        self.assertEqual(release.section(CHANGELOG, "1.7.0"), "### Added\n- A feature.")
        self.assertEqual(release.section(CHANGELOG, "Unreleased"), "### Fixed\n- A fix.")
        self.assertIsNone(release.section(CHANGELOG, "9.9.9"))

    def test_promote_moves_entries_under_new_version(self):
        out = release.promote_unreleased(CHANGELOG, "1.7.1", "2026-11-15")
        self.assertEqual(release.section(out, "Unreleased"), "")
        self.assertEqual(release.section(out, "1.7.1"), "### Fixed\n- A fix.")
        self.assertEqual(release.check_texts(release.set_app_version(APP, "1.7.1"), out), [])

    def test_consistent_texts_pass(self):
        self.assertEqual(release.check_texts(APP, CHANGELOG), [])

    def test_version_mismatch_is_reported(self):
        problems = release.check_texts(release.set_app_version(APP, "1.8.0"), CHANGELOG)
        self.assertTrue(any("App.Version is 1.8.0" in p for p in problems))

    def test_order_and_dates_are_checked(self):
        bad = CHANGELOG.replace("## [1.6.0] - 2026-11-13", "## [1.8.0]")
        problems = release.check_texts(APP, bad)
        self.assertTrue(any("needs a date" in p for p in problems))
        self.assertTrue(any("out of order" in p for p in problems))

    def test_unreleased_must_come_first(self):
        bad = CHANGELOG.replace("## [Unreleased]\n", "")
        self.assertTrue(any("[Unreleased]" in p for p in release.check_texts(APP, bad)))


class TagTests(unittest.TestCase):
    def test_unchanged_released_version_passes(self):
        self.assertEqual(release.check_against_tags("1.7.0", CHANGELOG, {"1.7.0": CHANGELOG}), [])

    def test_new_entries_under_released_version_fail(self):
        edited = CHANGELOG.replace("- A feature.", "- A feature.\n- Sneaked in.")
        problems = release.check_against_tags("1.7.0", edited, {"1.7.0": CHANGELOG})
        self.assertTrue(any("already released" in p for p in problems))

    def test_older_released_notes_are_frozen_after_a_bump(self):
        edited = CHANGELOG.replace("- Older.", "- Older.\n- Sneaked in.")
        problems = release.check_against_tags("1.8.0", edited, {"1.6.0": CHANGELOG, "1.7.0": CHANGELOG})
        self.assertTrue(any("v1.6.0 is already released" in p for p in problems))

    def test_behind_latest_tag_fails(self):
        problems = release.check_against_tags("1.7.0", CHANGELOG, {"1.7.0": CHANGELOG, "1.8.0": None})
        self.assertTrue(any("behind the latest tag v1.8.0" in p for p in problems))

    def test_unreleased_version_passes(self):
        self.assertEqual(release.check_against_tags("1.8.0", CHANGELOG, {"1.7.0": CHANGELOG}), [])


class PublishCommandTests(unittest.TestCase):
    def test_existing_release_is_left_alone(self):
        self.assertIsNone(release.publish_command("v1.8.0", "abc", tag_exists=True, release_exists=True))

    def test_new_version_tags_the_pushed_commit(self):
        command = release.publish_command("v1.8.0", "abc", tag_exists=False, release_exists=False)
        self.assertEqual(command[:4], ["gh", "release", "create", "v1.8.0"])
        self.assertIn("--target", command)
        self.assertEqual(command[command.index("--target") + 1], "abc")

    def test_missing_release_uses_existing_tag_without_moving_it(self):
        command = release.publish_command("v1.8.0", "abc", tag_exists=True, release_exists=False)
        self.assertIn("--verify-tag", command)
        self.assertNotIn("--target", command)


if __name__ == "__main__":
    unittest.main()
