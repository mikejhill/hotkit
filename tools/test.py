#!/usr/bin/env python3
"""Test orchestrator for hotkit.

  python tools/test.py lint          static checks (no AutoHotkey needed)
  python tools/test.py validate      AutoHotkey /Validate on every entry script
  python tools/test.py unit          headless unit tests (tests/unit)
  python tools/test.py integration   --check / --list-actions against fixtures, docs sync
  python tools/test.py e2e           live process driven by synthetic keystrokes
  python tools/test.py all           everything above, in order
  python tools/test.py mutation      mutation testing (slow; see tools/mutate.py)

Exit status is non-zero when any selected stage fails.
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ahk  # noqa: E402
import lint  # noqa: E402

REPO = ahk.REPO
MAIN = REPO / "src" / "Main.ahk"
ENTRY_SCRIPTS = [MAIN, REPO / "tests/unit/RunUnit.ahk", REPO / "tests/e2e/RunE2E.ahk"]


def stage_lint() -> bool:
    return lint.main([]) == 0


def stage_validate() -> bool:
    ok = True
    for script in ENTRY_SCRIPTS:
        r = ahk.validate(script)
        status = "ok" if r.code == 0 else "FAIL"
        print(f"validate {script.relative_to(REPO)}: {status}")
        if r.code != 0:
            print(r.out)
            ok = False
    return ok


def _tap(result: ahk.Result, name: str) -> bool:
    print(result.out)
    if result.timed_out:
        print(f"{name}: timed out")
    return result.code == 0


def stage_unit(filter_: str = "") -> bool:
    args = [f"--filter={filter_}"] if filter_ else []
    return _tap(ahk.run(REPO / "tests/unit/RunUnit.ahk", *args, timeout=300), "unit")


def stage_integration() -> bool:
    ok = True
    fixtures = REPO / "tests/integration/fixtures"
    expectations = json.loads((REPO / "tests/integration/expectations.json").read_text())
    cases = [(REPO / "config/config.example.json", {"exit": 0, "contains": ["OK"]})]
    cases += [(fixtures / name, exp) for name, exp in expectations.items()]
    with tempfile.TemporaryDirectory() as empty_dir:
        for path, exp in cases:
            r = ahk.run(MAIN, "--check", "--no-plugin-sync", "--config-dir", ahk.to_ahk_path(empty_dir),
                        "--config", ahk.to_ahk_path(path))
            problems = []
            if r.code != exp["exit"]:
                problems.append(f"exit {r.code}, expected {exp['exit']}")
            for needle in exp["contains"]:
                if needle not in r.out:
                    problems.append(f"missing output: {needle!r}")
            print(f"integration {path.name}: {'ok' if not problems else 'FAIL'}")
            if problems:
                ok = False
                print("  " + "\n  ".join(problems))
                print("  output:\n    " + r.out.replace("\n", "\n    "))
        ok = check_actions_doc(empty_dir) and ok
    ok = check_example_plugins() and ok
    return check_plugin_sync() and ok


EXAMPLE_ACTIONS = {
    "breakReminder.now", "breakReminder.togglePause", "breakReminder.status",
    "quickNote.add", "quickNote.open",
    "stopwatch.toggle", "stopwatch.lap", "stopwatch.reset", "stopwatch.show",
}


def check_example_plugins() -> bool:
    """examples/plugins load as a user's plugins, with the example config and with bad settings."""
    import shutil

    stub = REPO / "local" / "plugins.generated.ahk"
    backup = stub.read_bytes() if stub.exists() else None
    example_config = REPO / "examples/plugins/config.example.jsonc"
    ok = True
    try:
        with tempfile.TemporaryDirectory() as cfg_dir:
            shutil.copytree(REPO / "examples/plugins", Path(cfg_dir) / "plugins")
            bad_config = Path(cfg_dir) / "bad.json"
            bad_config.write_text('{ "plugins": { "breakReminder": { "intervalMinutes": 0 } } }', encoding="utf-8")
            base = ["--config-dir", ahk.to_ahk_path(cfg_dir), "--config"]
            steps = [
                ("sync", ["--sync-plugins", *base, ahk.to_ahk_path(example_config)], 0, "plugins: 3"),
                ("check", ["--check", *base, ahk.to_ahk_path(example_config)], 0, "OK"),
                ("bad settings", ["--check", *base, ahk.to_ahk_path(bad_config)], 1,
                 "plugin 'breakReminder': intervalMinutes must be a positive number"),
            ]
            for name, args, code, needle in steps:
                r = ahk.run(MAIN, *args)
                good = r.code == code and needle in r.out
                print(f"integration example plugins {name}: {'ok' if good else 'FAIL'}")
                if not good:
                    ok = False
                    print("  output:\n    " + r.out.replace("\n", "\n    "))
            r = ahk.run(MAIN, "--list-actions", *base, ahk.to_ahk_path(example_config))
            found = set()
            if r.code == 0 and "[" in r.out:
                found = {a["id"] for a in json.loads(r.out[r.out.index("["):]) if a["module"].startswith("plugin:")}
            missing = EXAMPLE_ACTIONS - found
            print(f"integration example plugins actions: {'ok' if not missing else 'FAIL'}")
            if missing:
                ok = False
                print("  missing: " + ", ".join(sorted(missing)) + "\n  output:\n    " + r.out.replace("\n", "\n    "))
    finally:
        if backup is None:
            stub.unlink(missing_ok=True)
        else:
            stub.write_bytes(backup)
    return ok


def check_plugin_sync() -> bool:
    """--check flags a stale plugin stub; --sync-plugins fixes it."""
    stub = REPO / "local" / "plugins.generated.ahk"
    backup = stub.read_bytes() if stub.exists() else None
    ok = True
    try:
        with tempfile.TemporaryDirectory() as cfg_dir:
            plugins = Path(cfg_dir) / "plugins"
            plugins.mkdir()
            (plugins / "Hello.ahk").write_text('App.AddPlugin("hello", (s) => ActionRegistry.Register('
                                               '"hello.world", (*) => 0))\n', encoding="utf-8")
            config = ["--config-dir", ahk.to_ahk_path(cfg_dir), "--config",
                      ahk.to_ahk_path(REPO / "config/config.example.json")]
            steps = [
                (["--check"], 1, "Plugin list changed"),
                (["--sync-plugins"], 0, "plugins: 1 (stub updated)"),
                (["--check"], 0, "plugins: 1"),
            ]
            for args, code, needle in steps:
                r = ahk.run(MAIN, *args, *config)
                good = r.code == code and needle in r.out
                print(f"integration plugin sync {' '.join(args)}: {'ok' if good else 'FAIL'}")
                if not good:
                    ok = False
                    print("  output:\n    " + r.out.replace("\n", "\n    "))
    finally:
        if backup is None:
            stub.unlink(missing_ok=True)
        else:
            stub.write_bytes(backup)
    return ok


def list_actions(config_dir: str) -> list[dict]:
    r = ahk.run(MAIN, "--list-actions", "--no-plugin-sync", "--config-dir", ahk.to_ahk_path(config_dir),
                "--config", ahk.to_ahk_path(REPO / "config/config.example.json"))
    if r.code != 0:
        raise RuntimeError("--list-actions failed:\n" + r.out)
    start = r.out.index("[")
    return [a for a in json.loads(r.out[start:]) if not a["module"].startswith("plugin:")]


def check_actions_doc(config_dir: str) -> bool:
    """docs/actions.md must match the registered actions (regenerate with tools/gen_docs.py)."""
    import gen_docs

    actions = list_actions(config_dir)
    expected = gen_docs.render(actions)
    current = (REPO / "docs/actions.md").read_text(encoding="utf-8")
    if current != expected:
        print("integration docs/actions.md: FAIL (stale; run python tools/gen_docs.py)")
        return False
    print(f"integration docs/actions.md: ok ({len(actions)} actions)")
    return True


def stage_e2e() -> bool:
    stub = REPO / "local" / "plugins.generated.ahk"
    backup = stub.read_bytes() if stub.exists() else None
    try:
        return _tap(ahk.run(REPO / "tests/e2e/RunE2E.ahk", timeout=300), "e2e")
    finally:
        # The e2e app rewrites the plugin stub for its fixture; restore the developer's.
        if backup is None:
            stub.unlink(missing_ok=True)
        else:
            stub.write_bytes(backup)


def stage_mutation(extra: list[str]) -> bool:
    import mutate

    return mutate.main(extra) == 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["lint", "validate", "unit", "integration", "e2e", "all", "mutation"])
    parser.add_argument("--filter", default="", help="unit test name filter")
    args, extra = parser.parse_known_args(argv)
    stages = {
        "lint": stage_lint,
        "validate": stage_validate,
        "unit": lambda: stage_unit(args.filter),
        "integration": stage_integration,
        "e2e": stage_e2e,
    }
    if args.stage == "mutation":
        return 0 if stage_mutation(extra) else 1
    selected = list(stages) if args.stage == "all" else [args.stage]
    failed = []
    for name in selected:
        print(f"==> {name}")
        if not stages[name]():
            failed.append(name)
    print("==> " + ("FAILED: " + ", ".join(failed) if failed else "all stages passed"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
