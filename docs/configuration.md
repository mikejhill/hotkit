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
| `tray` | Tray icon and extra tray menu items |
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
| `onRelease` | Action to run when the key, or the binding's modifier key, is released (press-and-hold) |
| `onNextKey` | Action to run on the next press of any other key, which is consumed (see below) |
| `onCancel` | With `onNextKey`: action to run instead when that key is Escape |
| `exclusive` | Name shared by hold and `onNextKey` bindings; only one of them is active at a time |
| `gestures` | `{ "tap", "doubleTap", "hold", "holdMs": 500, "doubleTapMs": 250 }` instead of `action` |
| `enabled` | `false` skips the binding |

An action reference (in `onRelease`, `gestures`, `tray.items`) is either an id
string or `{ "action": "id", "args": [...] }`.

Two bindings conflict when they share keys, modifier, group and `whenActive`
and can be live on the same layer. Both are reported and the later one is
skipped. A binding limited to layers and one on every layer don't conflict: on
those layers, the layer binding wins.

### Hold and press-then-next-key

Both run one action to start something and another to stop it, such as a
dictation tool's start/stop toggle. Key repeat never starts it twice.

```jsonc
"bindings": [
  // Hold: stops when Space or CapsLock is released, whichever comes first.
  { "modifier": "caps", "keys": "Space", "action": "run", "args": ["dictate.exe --toggle", "Hide"],
    "onRelease": { "action": "run", "args": ["dictate.exe --toggle", "Hide"] }, "exclusive": "dictation" },
  // Press: stops on the next press of any other key, which the focused app never sees.
  { "modifier": "caps", "keys": "^Space", "action": "run", "args": ["dictate.exe --toggle", "Hide"],
    "onNextKey": { "action": "run", "args": ["dictate.exe --toggle", "Hide"] },
    "onCancel": { "action": "run", "args": ["dictate.exe --cancel", "Hide"] }, "exclusive": "dictation" }
]
```

- A hold binding (`onRelease`) ends when its key or its modifier key is
  released. Other modifiers in the chord, such as Shift in `+Space`, can be let
  go without ending it.
- A press-then-next-key binding (`onNextKey`) ends on the next key press. That
  key is consumed; Escape runs `onCancel` instead, when set. Ctrl, Shift, Alt
  and Win alone don't end it, and keys still held from the chord count only
  after they are released. Holding the key that ended it doesn't start a new
  one, so pressing the same chord again just stops.
- Bindings with the same `exclusive` name are never active together: pressing
  one while another is active stops that one and starts nothing.
- When one of these ends while a modifier key is still held (CapsLock after
  letting go of Space), that modifier's other bindings stay off until it is
  released, so a tool that types or pastes when it stops isn't mistaken for a
  chord. Hold and press-then-next-key bindings still work meanwhile.

### Modifiers

```jsonc
"settings": { "keyboard": { "capsLock": "AlwaysOff" } },
"modifiers": { "caps": { "key": "CapsLock", "label": "CapsLock" } },
"bindings": [ { "modifier": "caps", "keys": "N", "action": "app.toggle", "args": ["notepad"] } ]
```

A binding on a modifier fires only when the Ctrl, Shift, Alt, or Win keys in its
`keys` are physically pressed, so keystrokes another program injects while the
modifier key is held (a dictation tool pasting with Ctrl+V, say) reach the app.

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
| `power` | `enabled` (on by default): stay-awake toggles and `monitors.off`; see [stay-awake.md](stay-awake.md) |
| `trayIcons` | `enabled`, `intervalSeconds`: keep all notification-area icons visible |
| `taskSwitcher` | `ignore: [{ exe, title, emptyTitle }]` windows skipped by `window.activateLast` |
| `windowRules` | `pollMs`, `rules: [{ match, alwaysOnTop }]` enforced on matching windows |

## Tray

```jsonc
"tray": {
  "icon": "icons/my-icon.ico",
  "items": [
    { "label": "Toggle &Theme", "action": "theme.toggle" },
    { "separator": true },
    { "label": "Apps", "items": [ { "label": "Notepad", "action": "app.toggle", "args": ["notepad"] } ] }
  ]
}
```

### Tray icon

hotkit shows its own icon (`assets/hotkit.ico`) unless `tray.icon` names
another one:

| Value | Meaning |
| --- | --- |
| *(omitted)*, `""` or `null` | The bundled hotkit icon |
| `"icons/my-icon.ico"` | A relative path, looked up next to `config.json` |
| `"C:/Icons/work.ico"`, `"%OneDrive%/icons/x.ico"`, `"~/icons/x.ico"` | An absolute path; `%VAR%` and `~` are expanded |
| `"shell32.dll"` | A bare file name not found next to `config.json` is looked up in `System32` |
| `{ "file": "imageres.dll", "index": 77 }` | Icon number `index` (1-based) in a multi-icon `.dll`, `.exe` or `.icl`; a negative number is a resource ID |

If the file is missing, the object form has no `file`, `index` isn't a
non-zero whole number, or Windows can't load the icon, hotkit uses its default
icon and lists the reason under *Show Config Problems* (and in `hotkit.log`).

While a stay-awake toggle is on, hotkit draws a muted coral circle with a
near-white "!" and a dark outline in the top-right corner of whichever icon
is in use; see [stay-awake.md](stay-awake.md).
`--check` reports the same problems, except an icon that exists but fails to
load, which is only detected when the app runs.

To regenerate the default icon after changing its design, run
`uv run tools/make_icon.py --preview .tmp/v9-icon-preview.png` (Pillow only).
It writes all eight ICO sizes and a nearest-neighbour preview on light and dark
taskbar backgrounds. With Pillow installed, `python tools/make_icon.py` also works.

To regenerate the README marks and social preview, run
`uv run --with pillow --with fonttools tools/make_brand.py`. It shares the palette
and E6 keycap geometry in `tools/make_icon.py` and writes `assets/brand/` plus
`.tmp/v9-brand-light.png` and `.tmp/v9-brand-dark.png`, without rewriting the icon.
The wordmark uses the bundled `assets/brand/fonts/JetBrainsMono[wght].ttf`,
instanced at Medium (`wght=500`). fontTools converts the glyph outlines to SVG
paths, so the README needs no installed fonts. Pillow renders the PNGs from the
same Medium instance. The font's SIL Open Font License is bundled in
`assets/brand/fonts/OFL.txt`, fetched from the
[JetBrains Mono repository](https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/OFL.txt).

Upload `assets/brand/social-preview.png`
manually in the GitHub repository's **Settings > General > Social preview**
to use it for shared repository links.
