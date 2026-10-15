# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `app.cycle`: switch between an app's windows (launches it if none are open).
- `--sync-plugins`; `--check` now reports a stale plugin list instead of unknown plugin actions.

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
