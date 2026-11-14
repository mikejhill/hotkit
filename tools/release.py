#!/usr/bin/env python3
"""Release tooling for hotkit. See RELEASING.md.

  python tools/release.py prepare [--bump patch|minor|major | --version X.Y.Z]
      Move [Unreleased] changelog entries under a new version and set App.Version.
  python tools/release.py check
      Check that App.Version, CHANGELOG.md and the version tags agree (also run by lint).
  python tools/release.py notes [X.Y.Z]
      Print a version's changelog entries (default: App.Version).
  python tools/release.py publish [--dry-run]
      Tag and create the GitHub release for App.Version if it does not exist yet.
      Run by .github/workflows/release.yml after CI passes on main.

App.Version in src/Core/App.ahk is the version's single source of truth.
"""
from __future__ import annotations

import argparse
import datetime
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "src" / "Core" / "App.ahk"
CHANGELOG = REPO / "CHANGELOG.md"

VERSION_LINE = re.compile(r'^(\s*static Version := ")(\d+\.\d+\.\d+)(")', re.M)
HEADING = re.compile(r"^## \[([^\]]+)\](?: - (\S+))?[ \t]*$", re.M)
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
BUMPS = ("patch", "minor", "major")


class ReleaseError(Exception):
    pass


Version = tuple[int, int, int]


def parse_version(text: str) -> Version:
    m = SEMVER.match(text)
    if not m:
        raise ReleaseError(f"not a version (X.Y.Z): {text!r}")
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def fmt(v: Version) -> str:
    return ".".join(map(str, v))


def bump(v: Version, kind: str) -> Version:
    major, minor, patch = v
    if kind == "major":
        return major + 1, 0, 0
    if kind == "minor":
        return major, minor + 1, 0
    return major, minor, patch + 1


# --- Pure text helpers (unit-tested) -------------------------------------

def app_version(app_text: str) -> str:
    m = VERSION_LINE.search(app_text)
    if not m:
        raise ReleaseError("src/Core/App.ahk has no `static Version := \"X.Y.Z\"` line")
    return m.group(2)


def set_app_version(app_text: str, version: str) -> str:
    return VERSION_LINE.sub(lambda m: m.group(1) + version + m.group(3), app_text, count=1)


def headings(changelog: str) -> list[tuple[str, str | None, int, int]]:
    """(name, date, body_start, body_end) for each `## [...]` heading."""
    found = list(HEADING.finditer(changelog))
    out = []
    for i, m in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(changelog)
        out.append((m.group(1), m.group(2), m.end(), end))
    return out


def section(changelog: str, name: str) -> str | None:
    for heading, _, start, end in headings(changelog):
        if heading == name:
            return changelog[start:end].strip()
    return None


def infer_bump(entries: str) -> str:
    """Semver bump implied by Keep a Changelog subsections (see RELEASING.md)."""
    kinds = {k.strip().lower() for k in re.findall(r"^### (.+)$", entries, re.M)}
    if "removed" in kinds or re.search(r"\*\*breaking", entries, re.I):
        return "major"
    if kinds & {"added", "changed", "deprecated"}:
        return "minor"
    if kinds & {"fixed", "security"}:
        return "patch"
    raise ReleaseError("cannot infer the bump: [Unreleased] has no Added/Changed/Deprecated/Removed/"
                       "Fixed/Security subsection; pass --bump")


def promote_unreleased(changelog: str, version: str, date: str) -> str:
    marker = "## [Unreleased]\n"
    if marker not in changelog:
        raise ReleaseError("CHANGELOG.md has no `## [Unreleased]` heading")
    return changelog.replace(marker, f"{marker}\n## [{version}] - {date}\n", 1)


def check_texts(app_text: str, changelog: str) -> list[str]:
    """Consistency problems between App.ahk and CHANGELOG.md (no git needed)."""
    problems = []
    try:
        version = app_version(app_text)
    except ReleaseError as e:
        return [str(e)]
    found = headings(changelog)
    if not found or found[0][0] != "Unreleased":
        problems.append("CHANGELOG.md: the first `## ` heading must be `## [Unreleased]`")
    released = [(n, d) for n, d, _, _ in found if n != "Unreleased"]
    if any(n == "Unreleased" for n, _, _, _ in found[1:]):
        problems.append("CHANGELOG.md: more than one `## [Unreleased]` heading")
    previous = None
    for name, date in released:
        if not SEMVER.match(name):
            problems.append(f"CHANGELOG.md: heading [{name}] is not a version")
            continue
        if not date or not DATE.match(date):
            problems.append(f"CHANGELOG.md: [{name}] needs a date: `## [{name}] - YYYY-MM-DD`")
        v = parse_version(name)
        if previous is not None and v >= previous:
            problems.append(f"CHANGELOG.md: [{name}] is out of order (newest first)")
        previous = v
    if released and released[0][0] != version:
        problems.append(f"App.Version is {version} but the newest CHANGELOG.md release is "
                        f"[{released[0][0]}]; run `python tools/release.py prepare`")
    return problems


def check_against_tags(version: str, changelog: str, tags: dict[str, str | None]) -> list[str]:
    """Problems with App.Version given existing tags ({version: changelog text at that tag})."""
    v = parse_version(version)
    problems = []
    newer = sorted((parse_version(t) for t in tags if parse_version(t) > v), reverse=True)
    if newer:
        problems.append(f"App.Version {version} is behind the latest tag v{fmt(newer[0])}; "
                        "update your branch from main")
    for tagged, tagged_changelog in sorted(tags.items(), key=lambda kv: parse_version(kv[0])):
        released = section(tagged_changelog, tagged) if tagged_changelog is not None else None
        if released is not None and section(changelog, tagged) != released:
            problems.append(f"v{tagged} is already released with different notes; release new "
                            "entries with `python tools/release.py prepare` instead of editing "
                            f"[{tagged}]")
    return problems


def publish_command(tag: str, sha: str, tag_exists: bool, release_exists: bool) -> list[str] | None:
    """The `gh` command that publishes `tag`, or None when it is already released.

    An existing tag is never moved: a missing release is created on the tag as it is.
    """
    if release_exists:
        return None
    command = ["gh", "release", "create", tag, "--title", tag, "--latest"]
    return command + (["--verify-tag"] if tag_exists else ["--target", sha])


# --- Git and GitHub -------------------------------------------------------
def git(*args: str, check: bool = True) -> str:
    r = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True, encoding="utf-8")
    if check and r.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def local_tags() -> list[str]:
    return [t[1:] for t in git("tag", "--list", "v*").split() if SEMVER.match(t[1:])]


def tag_changelogs() -> dict[str, str | None]:
    out: dict[str, str | None] = {}
    for t in local_tags():
        r = subprocess.run(["git", "show", f"v{t}:CHANGELOG.md"], cwd=REPO, capture_output=True,
                           text=True, encoding="utf-8")
        out[t] = r.stdout if r.returncode == 0 else None
    return out


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def check_repo() -> list[str]:
    app_text, changelog = read(APP), read(CHANGELOG)
    problems = check_texts(app_text, changelog)
    if not problems:
        problems += check_against_tags(app_version(app_text), changelog, tag_changelogs())
    return problems


# --- Commands -------------------------------------------------------------

def cmd_prepare(args: argparse.Namespace) -> int:
    if not args.no_fetch:
        git("fetch", "--tags", "--quiet", "origin")
    app_text, changelog = read(APP), read(CHANGELOG)
    entries = section(changelog, "Unreleased")
    if not entries:
        raise ReleaseError("nothing to release: [Unreleased] in CHANGELOG.md is empty")
    tags = [parse_version(t) for t in local_tags()]
    base = max([parse_version(app_version(app_text)), *tags])
    if args.version:
        new = parse_version(args.version)
        kind = "explicit"
        if new <= base:
            raise ReleaseError(f"{args.version} must be greater than {fmt(base)}")
    else:
        kind = args.bump or infer_bump(entries)
        new = bump(base, kind)
    version = fmt(new)
    if new in tags:
        raise ReleaseError(f"tag v{version} already exists")
    date = args.date or datetime.date.today().isoformat()
    write(CHANGELOG, promote_unreleased(changelog, version, date))
    write(APP, set_app_version(app_text, version))
    print(f"Prepared {version} ({kind} bump from {fmt(base)}): updated CHANGELOG.md and src/Core/App.ahk.")
    print(f"Commit as: chore: release v{version}")
    return 0


def cmd_check(_: argparse.Namespace) -> int:
    problems = check_repo()
    for p in problems:
        print(f"release: {p}")
    if not problems:
        print(f"release: App.Version {app_version(read(APP))} is consistent")
    return 1 if problems else 0


def cmd_notes(args: argparse.Namespace) -> int:
    version = args.version or app_version(read(APP))
    entries = section(read(CHANGELOG), version)
    if entries is None:
        raise ReleaseError(f"CHANGELOG.md has no [{version}] section")
    print(entries)
    return 0


def cmd_publish(args: argparse.Namespace) -> int:
    problems = check_repo()
    if problems:
        raise ReleaseError("; ".join(problems))
    version = app_version(read(APP))
    tag = f"v{version}"
    tag_exists = bool(git("ls-remote", "--tags", "origin", f"refs/tags/{tag}").strip())
    release_exists = subprocess.run(["gh", "release", "view", tag], cwd=REPO, capture_output=True).returncode == 0
    sha = git("rev-parse", "HEAD").strip()
    command = publish_command(tag, sha, tag_exists, release_exists)
    if command is None:
        print(f"{tag} is already released; nothing to publish.")
        return 0
    entries = section(read(CHANGELOG), version)
    if not entries:
        raise ReleaseError(f"CHANGELOG.md has no entries under [{version}]")
    if args.dry_run:
        print(f"Would run: {' '.join(command)} --notes-file <notes>\nNotes:\n{entries}")
        return 0
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(entries + "\n")
    try:
        subprocess.run([*command, "--notes-file", f.name], cwd=REPO, check=True)
    finally:
        os.unlink(f.name)
    print(f"Published {tag}.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare", help="promote [Unreleased] to a new version")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--bump", choices=BUMPS, help="override the inferred bump")
    group.add_argument("--version", help="exact version (X.Y.Z)")
    p.add_argument("--date", help="release date (default: today)")
    p.add_argument("--no-fetch", action="store_true", help="do not fetch tags from origin first")
    p.set_defaults(func=cmd_prepare)
    p = sub.add_parser("check", help="check version consistency")
    p.set_defaults(func=cmd_check)
    p = sub.add_parser("notes", help="print a version's changelog entries")
    p.add_argument("version", nargs="?")
    p.set_defaults(func=cmd_notes)
    p = sub.add_parser("publish", help="tag and create the GitHub release for App.Version")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_publish)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ReleaseError as e:
        print(f"release: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
