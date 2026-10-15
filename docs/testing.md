# Testing

```powershell
python tools\test.py lint          # static checks, no AutoHotkey needed
python tools\test.py validate      # AutoHotkey /Validate on entry scripts
python tools\test.py unit          # tests/unit, headless
python tools\test.py integration   # --check against fixtures; docs/actions.md in sync
python tools\test.py e2e           # live app driven by synthetic keystrokes
python tools\test.py all           # all of the above
python tools\test.py mutation      # mutation score (tools/mutate.py)
```

Set `AHK_EXE` if `AutoHotkey64.exe` is not on `PATH`. On Linux the tools run
AutoHotkey under Wine and Xvfb (`AHK_WRAPPER`, default `xvfb-run -a wine`).

| Layer | What it proves | Where |
| --- | --- | --- |
| Lint | Syntax hygiene, AHK v1 leftovers, personal paths / private terms, every unit test file included, example config matches schema | `tools/lint.py` |
| Unit | Pure logic: config parsing, action registry, binding parsing/conflicts/contexts, hotkey text, window matching, brightness/scale math, plugin stub rendering | `tests/unit/*.Test.ahk` |
| Integration | The real entry point validates good and broken configs with the right exit codes and messages | `tests/integration` |
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
CI runs every mutant weekly and fails below 90%. Remaining survivors are equivalent
mutants (e.g. `<` vs `<=` where both branches give the same result). Thin Win32
and GUI wrappers are excluded with `; mutate: off` / `; mutate: on` comments;
those are covered by the end-to-end suite.
