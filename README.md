# hotkit

**A config-driven hotkey toolkit for Windows, built on AutoHotkey v2.**

[![CI](https://github.com/mikejhill/hotkit/actions/workflows/ci.yml/badge.svg)](https://github.com/mikejhill/hotkit/actions/workflows/ci.yml)
[![AutoHotkey v2](https://img.shields.io/badge/AutoHotkey-v2.0-334455)](https://www.autohotkey.com/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

My personal Windows desktop automation, published
as a reusable engine. The repository holds **capabilities**: window toggling,
quick windows, display brightness and scale, layers, gestures, a shortcut
overlay. **Which key does what** lives in one JSON file outside the repository.

> This is a personal toolkit, shared because others may find the pieces useful.
> It is maintained for one setup; issues and PRs are welcome but may be declined
> if they don't fit. See [docs/philosophy.md](docs/philosophy.md).

## Features

| | |
| --- | --- |
| **Shortcuts in JSON** | Every hotkey is a line in `config.json`: keys, action, arguments, description. Validated at load, with conflict detection. |
| **Shortcut overlay** | Searchable list of every active shortcut (tray › *Show Shortcuts*, or bind `osd.toggle`). |
| **Layers and gestures** | Hold-a-key layers (e.g. CapsLock as a modifier), tap / double-tap / hold on one key, press-and-release actions, per-app bindings, runtime-toggleable groups. |
| **Quick windows** | Summon and dismiss any app as a floating window with one key. Generic; you define the instances. |
| **App toggles** | Focus, minimize, or launch an app from a hotkey. |
| **Display** | DDC/CI and WMI brightness, gamma dimming, Night Light strength, display scale stepping. |
| **Desktop** | Light/dark theme with wallpaper, media keys, always-on-top with an indicator, last-window switching, lock-key state. |
| **Plugins** | Drop an `.ahk` file into your config folder to add private actions. |
| **One config location** | `%USERPROFILE%\.config\hotkit\`, live-reloaded on save. |

## Quick start

1. Install [AutoHotkey v2.0](https://www.autohotkey.com/) (v2.0.30 or later).
2. Clone and run:
   ```powershell
   git clone https://github.com/mikejhill/hotkit.git
   cd hotkit
   .\src\Main.ahk
   ```
3. On first run, `config\config.example.json` is copied to
   `%USERPROFILE%\.config\hotkit\config.json`. Edit it from the tray
   (*Edit Config*); the app restarts when you save.
4. Press the overlay hotkey (`RCtrl+RAlt+/` in the example) to see every shortcut.

To start at sign-in, put a shortcut to `src\Main.ahk` in `shell:startup`.

## Configuration in one example

```jsonc
{
  "layers": { "caps": { "key": "CapsLock" } },
  "apps": {
    "notepad": { "name": "Notepad", "run": "notepad.exe", "match": "ahk_exe notepad.exe" }
  },
  "bindings": [
    { "layer": "caps", "keys": "N", "action": "app.toggle", "args": ["notepad"] },
    { "keys": ">^>!PgUp", "action": "brightness.increase" },
    { "keys": "F23", "gestures": { "tap": "media.playPause", "hold": "media.next" } }
  ]
}
```

- [Configuration reference](docs/configuration.md)
- [Action reference](docs/actions.md) (generated)
- [Writing plugins](docs/plugins.md) and [example plugins](examples/plugins/README.md)

Validate a config without starting anything:

```powershell
AutoHotkey64.exe src\Main.ahk --check
```

## Repository layout

```
src/         Main.ahk, Core/ (config, actions, bindings, plugins, tray), Modules/, Lib/, Ui/
config/      config.example.json, config.schema.json
examples/    plugins/ (copyable example plugins)
tests/       unit/, integration/, e2e/ (AutoHotkey) + lib/TestRunner.ahk
tools/       test.py, lint.py, mutate.py, gen_docs.py
docs/        philosophy, architecture, configuration, actions, plugins, testing
local/       generated, git-ignored
```

## Development

```powershell
python tools\test.py all        # lint, validate, unit, integration, e2e
python tools\test.py mutation   # mutation score of the unit suite
```

Details: [docs/testing.md](docs/testing.md), [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
