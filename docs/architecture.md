# Architecture

```
src/Main.ahk
  ├─ Core/Paths        config directory resolution
  ├─ Core/Config       JSONC loading, dotted lookups
  ├─ Core/ActionRegistry   id → handler + metadata
  ├─ Core/Bindings     config bindings → live hotkeys (modifiers, layers, groups, gestures)
  ├─ Core/Plugins      discovers <config>\plugins\*.ahk, writes local\plugins.generated.ahk
  ├─ Core/Tray         tray menu
  ├─ Core/Updates      GitHub release checks, fast-forward install
  ├─ Core/App          startup, CLI flags, restart, config watch
  ├─ Ui/ShortcutOsd    searchable shortcut overlay
  ├─ Modules/*         register actions (Apps, QuickWindows, Windows, Desktop, Display)
  ├─ Lib/*             reusable classes with no knowledge of config
  └─ #Include *i local\plugins.generated.ahk
```

## Startup

1. **Plugin sync.** AutoHotkey resolves `#Include` before the script runs, so
   plugins outside the repository are included through a generated, git-ignored
   stub. If the plugin set changed, the stub is rewritten and the app restarts.
2. **Load config.** Copies the example on first run.
3. **Boot.** Core actions, then each module's `Register(cfg)`, then each plugin's
   init, then bindings are parsed and validated. Nothing touches the system yet;
   `--check` and `--list-actions` stop here.
4. **Run.** Modules' `Start(cfg)`, hotkeys registered, tray built, config watch
   started, `App.OnReady` hooks run.

## Actions

Every behavior is registered once:

```ahk
ActionRegistry.Register("window.toggleMinimized", (*) => ..., {
    module: "windows", description: "Minimize or restore the active window", params: "" })
```

Bindings, tray items, gestures and plugins refer to the id. `SafeInvoke` catches
errors and shows a toast so a failing action never kills the hotkey thread.
`docs/actions.md` is generated from the registry and checked in CI.

## Bindings

Each binding becomes a spec with a context key of
`modifier|layers|group|whenActive`. Specs sharing a context share one cached
`HotIf` predicate, so AutoHotkey evaluates each context once per keypress.
Modifiers test `GetKeyState(key, "P")`; layers compare against
`Bindings.activeLayer`. Conflicts are detected before anything is registered.
Layer bindings are registered before every-layer bindings on the same keys,
because AutoHotkey runs the earliest-created eligible variant: that is how a
layer binding overrides an every-layer one.

Binding kinds:

| Kind | Implementation |
| --- | --- |
| action | Hotkey runs `SafeInvoke` |
| action + `waitRelease` | Runs, then `KeyWait` |
| action + `onRelease` | Press runs once; a `*key` hotkey swallows repeats until the key is up; `~*key Up` or `~*<modifier key> Up`, whichever fires first, runs the release action |
| action + `onNextKey` | Press runs once and starts an `InputHook` with every key as a suppressed end key, except Ctrl/Shift/Alt/Win and the chord keys still held (re-armed by their `~*key Up` hotkeys). The end key runs `onNextKey`, or `onCancel` for Escape, is suppressed until released, and blocks hold/latch starts until then. While a latch waits, every other binding's `HotIf` is false, because hook hotkeys see keys before `InputHook` |
| `exclusive` | One stop callback per name in `Bindings._sessions`; a hold/latch press while one is set runs it instead of starting |
| gestures | `KeyWait` with `holdMs` decides hold; a timer of `doubleTapMs` separates tap from double-tap |

Simulated keys: `SimulatedKeys` installs a `WH_KEYBOARD_LL` hook after `Bindings.Apply()`. Windows calls the newest hook first, so it records each event's `LLKHF_INJECTED` flag before AutoHotkey's hook evaluates `#HotIf`. Binding contexts (unless `allowSimulated`) call `SimulatedKeys.Allows(hotkeyName)`, which blocks only a fresh injected event for the hotkey's own key and otherwise fails open. A 30-second timer re-installs the hook.

Remote sessions: `RemoteSessions` starts after `SimulatedKeys` and watches `EVENT_SYSTEM_FOREGROUND`. When a `settings.remoteWindows` window becomes active it calls `InstallKeybdHook(true, true)` 50, 300 and 1000 ms later (a forced re-install resets AutoHotkey's key state and puts its hook ahead of the client's), then re-installs the `SimulatedKeys` hook to keep that one first. A check is postponed while a key that the `SimulatedKeys` hook saw go down since activation is still held, so keys held right now are not forgotten; that hook also runs when only `remoteWindows` needs it. It also lifts a forced CapsLock state while the window is active. Modifier bindings are wrapped to send the modifier's key-up to the session before the action, and `yieldToRemote` adds `!RemoteSessions.IsActive()` to the context.

## Libraries

`src/Lib` holds standalone classes (window utilities, DDC/CI, WMI brightness,
JSON, toasts, Night Light, display scale, `QuickWindow`, `WindowMatcher`). They
take plain values, not config, and keep decisions in pure static methods
(`HotkeyText.Parse`, `WindowMatcher.Matches`, `GammaBrightness.GammaFor`,
`DisplayScale.StepBy`, ...) that the unit tests cover.

## Private code

Anything specific to one person or employer lives in the config folder, never
in the repository: the config file for preferences, plugins for code. The lint
stage rejects personal paths and any term listed in a local `.private-terms`
file.
