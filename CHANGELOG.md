# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Saving `config.json` could restart the app while the file was half written and show a "Could not load config" dialog. Reloads now wait for the file to settle, and a config that doesn't parse is reported in a toast while the app keeps its previous config.
- `app.toggle` with several windows raised a different one on each show; it now returns to the window focused last.
- Cloaking checks no longer fail without DWM (e.g. under Wine).
- A hidden quick window now reappears when activated another way (taskbar button, Alt+Tab) instead of staying invisible.
- `quickWindow.toggle` failed with "Target window not found" when the app was running but its window was closed to the tray; it now runs the launch command and brings that window back.

### Added
- `taskbar.activate` action: Win+<n> for taskbar slot n, bindable to any key (e.g. Caps+1..0). When a full-screen window has focus it focuses the desktop first, so the keystroke reaches Windows instead of the app. On a layer, Win stays held while the layer key is held, so repeated presses step through an app's windows like holding Win does. Held Shift/Ctrl/Alt pass through (Win+Shift+<n> new instance, Win+Ctrl+<n> last active window, Win+Alt+<n> jump list); bind with a `*` prefix (e.g. `"*1"`) so the layer binding fires with them.
- `window.sendBackward`, `window.sendToBack`, `window.bringForward`, `window.bringToFront`: restack the active window without minimizing it or taking focus from it. Stepping skips windows it doesn't overlap, and always-on-top windows stay in their own layer.
- `window.cycleNext` / `window.cyclePrevious`: Alt+Tab-style focus cycling through on-screen windows; each undoes the other.
- `desktop.focus` action: moves keyboard focus to the desktop without minimizing any window, so Win+<key>, Alt+Tab and other system shortcuts work while a full-screen app is capturing them.
- `hotkit.log` (in `%LOCALAPPDATA%\hotkit`, so a synced config directory has no shared writer) records each start, config problems, load failures, skipped reloads and unhandled errors.
- `tools/check.py` checks the real config and plugins, prints what the running app logged, and exits non-zero on any problem.
- The test tools find a standard AutoHotkey v2 install when `AutoHotkey64.exe` is not on `PATH`.
- Example plugins in `examples/plugins` (break reminder, quick note, stopwatch), loaded by the test suite.
- `app.cycle`: switch between an app's windows (launches it if none are open).
- `--sync-plugins`; `--check` now reports a stale plugin list instead of unknown plugin actions.
- Layer `suspendWhenActive`: pause a layer while a matching window is active, for windows with anti-keylogging protection that feed scrambled keystrokes to keyboard hooks and would otherwise fire random layer bindings.

## [1.0.0] - 2026-10-15

First public release; a rewrite of an earlier private collection.

### Added
- Action registry and JSON (with comments) configuration in `%USERPROFILE%\.config\hotkit`.
- Bindings with layers, groups, per-window contexts, gestures, press-and-release, and conflict detection.
- Searchable keyboard shortcut overlay.
- Generic quick windows and app toggles defined in config.
- Display brightness (DDC/CI, WMI, gamma, Night Light) and display scale actions.
- Theme, wallpaper, media, always-on-top, window switching, and window rule actions.
- Private plugins loaded from the config folder.
- `--check` and `--list-actions` command-line modes.
- Lint, unit, integration, end-to-end, and mutation tests; GitHub Actions CI.
