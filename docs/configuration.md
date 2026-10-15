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
a plugin restarts the app. Problems are listed under tray › *Show Config
Problems*; everything else keeps working. To check from a terminal:

```powershell
AutoHotkey64.exe src\Main.ahk --check [--config path\to\config.json]
```

## Top-level keys

| Key | Purpose |
| --- | --- |
| `settings` | `watchConfig`, `debug`, `keyboard.capsLock` / `keyboard.numLock` (`On`, `Off`, `AlwaysOn`, `AlwaysOff`) |
| `layers` | Keys that act as modifiers while held |
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
| `layer` | Only active while that layer's key is held |
| `group` | Only active while that group is enabled |
| `whenActive` | WinTitle; only active while a matching window is focused |
| `waitRelease` | Run once per press; ignore key repeat until release |
| `onRelease` | Action to run when the key is released (press-and-hold) |
| `gestures` | `{ "tap", "doubleTap", "hold", "holdMs": 500, "doubleTapMs": 250 }` instead of `action` |
| `enabled` | `false` skips the binding |

An action reference (in `onRelease`, `gestures`, `tray.items`) is either an id
string or `{ "action": "id", "args": [...] }`.

Two bindings conflict when they share keys, layer, group, and `whenActive`. Both
are reported and the later one is skipped.

### Layers

```jsonc
"settings": { "keyboard": { "capsLock": "AlwaysOff" } },
"layers": { "caps": { "key": "CapsLock", "label": "CapsLock" } },
"bindings": [ { "layer": "caps", "keys": "N", "action": "app.toggle", "args": ["notepad"] } ]
```

The layer key keeps its normal function unless you disable it (as above for
Caps Lock). `keyboard.toggleCapsLock` still toggles it on demand.

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

`app.toggle` focuses the first window matching `match` (WinTitle, RegEx title
mode), minimizes it if it is already active, or runs `run` when none exists.

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
