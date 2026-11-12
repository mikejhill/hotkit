# Configuration

All personal settings live in one folder:

| Order | Location |
| --- | --- |
| 1 | `--config-dir <dir>` command-line flag |
| 2 | `HOTKIT_CONFIG_DIR` environment variable |
| 3 | `%XDG_CONFIG_HOME%\hotkit` |
| 4 | `%USERPROFILE%\.config\hotkit` (default) |

```
hotkit\
  config.json        bindings, apps, quick windows, module settings
  plugins\*.ahk      optional private plugins (see plugins.md)
```

`config.json` is JSON with comments (`//`, `/* */`) and trailing commas allowed.
Point your editor at [`config/config.schema.json`](../config/config.schema.json)
with a `"$schema"` key for completion and validation. Paths accept `%VAR%` and a
leading `~`.

With `settings.watchConfig` on (the default), saving the file or adding/removing
a plugin restarts the app. The restart waits until the files have stopped
changing for one poll (about two seconds), so a save in progress is never read
half-written. If `config.json` then doesn't parse, the app keeps running with
the previous config and shows a toast instead of restarting. Problems are listed
under tray › *Show Config Problems*; everything else keeps working. To check
from a terminal:

```powershell
AutoHotkey64.exe src\Main.ahk --check [--config path\to\config.json]
python tools\check.py [--config path\to\config.json]
```

`tools\check.py` finds AutoHotkey (or `AHK_EXE`), refreshes the plugin list,
runs `--check`, then prints the warnings and errors the running app logged since
it last started. It exits non-zero when either has a problem.

The running app records each start, config problems, load failures, skipped
reloads and unhandled script errors in `%LOCALAPPDATA%\hotkit\hotkit.log`, so
anything shown as a dialog or toast can also be read afterwards. The log is
kept out of the config directory so that directory can be synced between
machines (with `--config-dir`, the log stays next to that config instead).

hotkit refuses to start when it inherits an app package's virtualized profile
(for example when launched from a shell inside a packaged desktop app). In that
state its registry writes never reach Windows, so features like tray-icon
promotion silently do nothing. Pass `--allow-virtualized` to start anyway.

## Top-level keys

| Key | Purpose |
| --- | --- |
| `settings` | `watchConfig`, `debug`, `keyboard.capsLock` / `keyboard.numLock` (`On`, `Off`, `AlwaysOn`, `AlwaysOff`) |
| `modifiers` | Keys that act as modifiers while held (e.g. CapsLock) |
| `layers` | Switchable sets of bindings; one is active at a time |
| `groups` | Named sets of bindings that can be switched on and off |
| `bindings` | The shortcuts |
| `apps` | Apps used by `app.toggle` and `app.launch` |
| `quickWindows` | Floating windows used by `quickWindow.*` |
| `modules` | Per-module settings; any module accepts `"enabled": false` |
| `tray` | Extra tray menu items |
| `plugins` | Settings handed to each plugin, keyed by plugin name |

## Bindings

```jsonc
{ "keys": ">^>!PgUp", "action": "brightness.adjust", "args": [5], "description": "Brighter" }
```

| Field | Meaning |
| --- | --- |
| `keys` | AutoHotkey hotkey: `^` Ctrl, `!` Alt, `+` Shift, `#` Win, `<`/`>` left/right, `A & B` combos, `UP` suffix for release |
| `action`, `args` | Action id and positional arguments ([actions.md](actions.md)) |
| `description` | Shown in the shortcut overlay; defaults to the action's description |
| `modifier` | Only active while that modifier's key is held |
| `layer` | Only active on that layer: a name, or a list of names. Omitted: every layer |
| `group` | Only active while that group is enabled |
| `whenActive` | WinTitle; only active while a matching window is focused |
| `waitRelease` | Run once per press; ignore key repeat until release |
| `onRelease` | Action to run when the key is released (press-and-hold) |
| `gestures` | `{ "tap", "doubleTap", "hold", "holdMs": 500, "doubleTapMs": 250 }` instead of `action` |
| `enabled` | `false` skips the binding |

An action reference (in `onRelease`, `gestures`, `tray.items`) is either an id
string or `{ "action": "id", "args": [...] }`.

Two bindings conflict when they share keys, modifier, group and `whenActive`
and can be live on the same layer. Both are reported and the later one is
skipped. A binding limited to layers and one on every layer don't conflict: on
those layers, the layer binding wins.

### Modifiers

```jsonc
"settings": { "keyboard": { "capsLock": "AlwaysOff" } },
"modifiers": { "caps": { "key": "CapsLock", "label": "CapsLock" } },
"bindings": [ { "modifier": "caps", "keys": "N", "action": "app.toggle", "args": ["notepad"] } ]
```

The modifier key keeps its normal function unless you disable it (as above for
Caps Lock). `keyboard.toggleCapsLock` still toggles it on demand.

`suspendWhenActive` (a WinTitle or a list of them) pauses the modifier while a
matching window is active. Use it for windows that scramble keystrokes sent to
keyboard hooks (anti-keylogging protection in some remote-access sign-in
windows), where a held modifier would otherwise fire bindings on random keys:

```jsonc
"modifiers": { "caps": { "key": "CapsLock", "suspendWhenActive": ["ahk_exe SecureLogin.exe"] } }
```

Before 1.2.0 modifiers were defined under `layers` and bindings named them with
`layer`. Such a config still works; `--check` and the tray report each one to
move.

### Layers

A layer is a set of bindings you switch to; exactly one layer is active at a
time. Bindings with a `layer` only fire on that layer (or any layer in a list);
bindings without one fire on every layer. The usual setup puts the switch keys
on every layer, here Caps+1..3:

```jsonc
"layers": {
  "1": { "label": "Main", "default": true },
  "2": { "label": "Games", "description": "Arrow keys on WASD" },
  "3": {}
},
"bindings": [
  { "modifier": "caps", "keys": "1", "action": "layer.activate", "args": ["1"] },
  { "modifier": "caps", "keys": "2", "action": "layer.activate", "args": ["2"] },
  { "modifier": "caps", "keys": "3", "action": "layer.activate", "args": ["3"] },
  { "layer": "1", "modifier": "caps", "keys": "N", "action": "app.toggle", "args": ["notepad"] },
  { "layer": "2", "keys": "w", "action": "send", "args": ["{Up}"] },
  { "layer": ["2", "3"], "keys": "F1", "action": "app.toggle", "args": ["notepad"] }
]
```

`layers` is either a list of names (`["1", "2", "3"]`, in that order) or an
object of name to settings, listed in natural order (2 before 10):

| Field | Meaning |
| --- | --- |
| `label` | Shown in toasts, the tray menu and the shortcut overlay. Default: `Layer <name>` for numbers, else the name |
| `description` | Second line of the toast, and shown in the tray menu |
| `default` | The layer to start on. Default: the first |

Switching shows a toast, checks the layer in tray › *Layer*, and is remembered
across restarts (in `state.json` beside `hotkit.log`), so saving the config
keeps you on the same layer. The shortcut overlay lists the active layer's
bindings plus those on every layer; tick *All layers* to see the rest. Actions:
`layer.activate`, `layer.next`, `layer.previous`.

### Groups

```jsonc
"groups": { "gaming": { "description": "Gaming keys", "enabled": false } },
"bindings": [
  { "keys": "F9", "action": "bindings.toggleGroup", "args": ["gaming"] },
  { "group": "gaming", "keys": "F1", "action": "send", "args": ["{Esc}"] }
]
```

## Apps

```jsonc
"apps": {
  "music": {
    "name": "Music",
    "run": "msedge.exe --app=https://music.example.com",
    "match": "Music ahk_exe msedge.exe",
    "options": ""
  }
}
```

`app.toggle` raises the app's window that you focused most recently (matched by
`match`, a WinTitle in RegEx title mode), minimizes it if it is already active,
or runs `run` when none exists. Hiding and showing with the same key returns to
the same window.
`app.cycle` switches between the app's windows instead: the most recent one
first, then each press rotates to the next. It skips windows on other virtual
desktops, never minimizes, and launches the app when no window exists. A common
pattern is `app.toggle` on a key and `app.cycle` on Shift plus the same key.

## Quick windows

A quick window is a normal app window that is shown and hidden with one key,
optionally floating on top and hidden from the taskbar.

```jsonc
"quickWindows": {
  "scratchpad": {
    "exe": "notepad.exe",
    "launch": "notepad.exe",
    "match": { "class": "Notepad", "topLevel": true },
    "toolWindow": true,
    "alwaysOnTop": true,
    "claimExisting": false,
    "multipleWindows": true,
    "launchTimeoutSeconds": 10,
    "size": { "width": 0.4, "height": 0.5 },
    "modes": []
  }
}
```

| Field | Meaning |
| --- | --- |
| `exe` | Process name to watch |
| `launch` | Command to start a new window; `{mode}` is replaced by the current mode |
| `match` | Window matcher: `exe`, `class`, `title` (RegEx), `titleNotEmpty`, `appUserModelId`, `visible`, `topLevel`, `minWidth`, `minHeight` |
| `toolWindow` | Hide from the taskbar and Alt+Tab while managed |
| `alwaysOnTop` | Keep above other windows |
| `claimExisting` | Adopt matching windows that were already open |
| `multipleWindows` | Allow `quickWindow.create` to open more |
| `size` | Fraction of the monitor work area |
| `modes` | Strings cycled by `quickWindow.cycleMode` |

Quick windows hide by turning fully transparent and click-through rather than minimizing, so showing them again is instant. A hidden window keeps its taskbar button and Alt+Tab entry (unless `toolWindow` is set); activating it from either reveals it.

## Modules

| Module | Settings |
| --- | --- |
| `displayBrightness` | `step` (10), `swapFallback` (85), `gamma: { min, max, default }` |
| `displayScale` | `setDpiPath` (path to a [SetDPI](https://github.com/imniko/SetDPI) build), `presets`, `debounceMs` |
| `alwaysOnTop` | `indicatorColor` (hex, `""` for none) |
| `theme` | `wallpaper: { light, dark }` (`"bing"`, a path, or `""`), `bing: { cacheDir, maxAgeDays }` |
| `trayIcons` | `enabled`, `intervalSeconds`: keep all notification-area icons visible |
| `taskSwitcher` | `ignore: [{ exe, title, emptyTitle }]` windows skipped by `window.activateLast` |
| `windowRules` | `pollMs`, `rules: [{ match, alwaysOnTop }]` enforced on matching windows |

## Tray

```jsonc
"tray": {
  "items": [
    { "label": "Toggle &Theme", "action": "theme.toggle" },
    { "separator": true },
    { "label": "Apps", "items": [ { "label": "Notepad", "action": "app.toggle", "args": ["notepad"] } ] }
  ]
}
```
