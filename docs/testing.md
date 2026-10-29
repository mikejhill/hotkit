# Testing

```powershell
python tools\test.py lint          # static checks, no AutoHotkey needed
python tools\test.py validate      # AutoHotkey /Validate on entry scripts
python tools\test.py unit          # tests/unit, headless
python tools\test.py integration   # --check against fixtures, plugin sync, example plugins, docs/actions.md in sync
python tools\test.py e2e           # live app driven by synthetic keystrokes
python tools\test.py all           # all of the above
python tools\test.py mutation      # mutation score (tools/mutate.py)
```

The tools use `AHK_EXE`, then `AutoHotkey64.exe` on `PATH`, then a standard
AutoHotkey v2 install under `%LOCALAPPDATA%\Programs` or `%ProgramFiles%`. On Linux the tools run
AutoHotkey under Wine and Xvfb (`AHK_WRAPPER`, default `xvfb-run -a wine`).

| Layer | What it proves | Where |
| --- | --- | --- |
| Lint | Syntax hygiene, AHK v1 leftovers, personal paths / private terms, every unit test file included, example config matches schema | `tools/lint.py` |
| Unit | Pure logic: config parsing, action registry, binding parsing/conflicts/contexts, hotkey text, window matching, brightness/scale math, plugin stub rendering, example plugin helpers | `tests/unit/*.Test.ahk` |
| Integration | The real entry point validates good and broken configs with the right exit codes and messages, and loads `examples/plugins` as user plugins | `tests/integration` |
| End-to-end / UX | A running instance: hotkeys fire actions, layers and groups gate them, the shortcut overlay opens and filters, config edits restart the app, plugins load | `tests/e2e/RunE2E.ahk` |
| Mutation | The unit suite fails when logic in Core and Lib is altered | `tools/mutate.py` |

## Writing unit tests

```ahk
class HotkeyTextTests {
    static Test_ParsesModifiers() {
        p := HotkeyText.Parse(">^>!PgUp")
        Assert.Equal("PgUp", p.key)
    }
}
```

Add the file to `tests/unit/RunUnit.ahk` (lint enforces it). Every static
method starting with `Test_` runs. Use `--filter=<text>` to run a subset.

## Mutation testing

`tools/mutate.py` flips one operator at a time (`=`/`!=`, `<`/`<=`, `&&`/`||`,
`true`/`false`, `+ 1`/`- 1`, `!`, early `return`) in a temporary copy of the
repository and reruns the unit suite. Mutants that don't load are excluded.
The independent Mutation tests workflow runs every mutant after pushes to `main`,
weekly, and on manual dispatch from `main`. It fails below 90%; mutation is never
a PR, merge, release, or `tools/test.py all` gate. This is the owner's standing
project setup preference. Existing running jobs are allowed to finish.

The separate Mutation alerts workflow tracks scores below the required threshold and
incomplete/tool failures in two deduplicated issues assigned to the repository
owner. Each update records the tested commit, run link, scope, score, and counts.
The owner triages within seven days: add missing assertions, repair tool failures,
and rerun. Do not lower
the score floor to clear an alert. Recurrences reopen the same tracker. Only a
complete, full-scope run at or above the configured 90% threshold resolves the
findings tracker. Equality passes; survivors alone never create findings issues
on passing scores. Survivor details remain in artifacts and summaries, and closing
a score tracker does not mean all mutants were fixed. Manual
samples and missing, cancelled, timed-out, or incomplete runs never resolve it.
A completed sample can demonstrate execution recovery but cannot create or clear
full-scope score findings. Missing or malformed threshold evidence raises an
execution alert rather than inventing a threshold.
Stale runs cannot overwrite newer tracker evidence. Artifacts remain available
for 30 days; issues retain the evidence after artifacts expire. Failed alert
publication remains visible in the Mutation alerts Actions run and is retried
by rerunning its failed job or by the next mutation run.

Runner errors and timeouts are incomplete evidence, never killed mutants. Mutants
that cannot load are excluded; a run with no valid mutants is incomplete.
Survivors may be equivalent mutants (e.g. `<` vs `<=` where both branches give
the same result), but require triage. Thin Win32
and GUI wrappers are excluded with `; mutate: off` / `; mutate: on` comments;
those are covered by the end-to-end suite.

Reporting tests run inside the existing lint gate without mutation execution:

```powershell
python -m unittest discover -s tests/tooling -p "test_*.py"
node --test tests/tooling/mutation_alerts.test.cjs
```
