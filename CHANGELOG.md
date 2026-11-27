# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.21.1] - 2026-11-27

### Fixed
- After leaving a `settings.suspendWhenActive` window, a forced CapsLock or NumLock state is applied again over the next few seconds, and a key toggled the wrong way is set back first. Before, CapsLock could stay on after you left a remote session that synced its lock state back to the local machine.

## [1.21.0] - 2026-11-27

### Changed
- Display text now writes the name as Hotkit and uses title case for labels: tray items, toast titles, dialog titles, the example configs' binding descriptions, and doc headings. The README logo and social preview spell it Hotkit too. Paths, the config folder, environment variables, and other identifiers stay lowercase.

## [1.20.0] - 2026-11-27

### Added
- `settings.suspendWhenActive` lists windows that get the keyboard to themselves. While one is active, hotkit suspends every shortcut, layer keys included, and lifts a forced CapsLock or NumLock state, so that window sees CapsLock as CapsLock. Use it for a remote session whose machine runs its own hotkit with the same keys. Focusing another window brings everything back, and the tray tooltip says when hotkit is paused.

## [1.19.1] - 2026-11-27

### Fixed
- Updating from the tray no longer refuses a valid checkout when hotkit was started through a junction, symlink, subst drive, or short (8.3) path, or when git prints warnings or trace output, which no longer read as uncommitted changes either. When git can't use the folder, the message now says why: git's own error, the checkout git found instead, or, when git can't confirm who owns the folder, the `safe.directory` command that trusts it.

## [1.19.0] - 2026-11-26

### Added
- `modules.windowCycle.continueMs` keeps a `window.cycleNext` or `window.cyclePrevious` cycle open for that long after its keys are released, so the next press continues the same cycle instead of starting over. Use it on a machine that receives relayed modifier chords, where the modifier is released after every press. If a different window has focus at the next press, a new cycle starts.

## [1.18.0] - 2026-11-25

### Added
- A binding on a modifier that sets `allowSimulated` now also fires when another program holds the modifier key and Ctrl, Shift, Alt, or Win, as a remote client does with forwarded keys. A relay key such as F13 can then serve as the modifier on the inner machine of a remote session, with its own Ctrl, Shift, and Alt variants. See [Relay keys as a modifier](docs/relay-keys.md#relay-keys-as-a-modifier).

## [1.17.2] - 2026-11-24

### Fixed
- A quick window that is hidden when hotkit exits or reloads now goes to the taskbar minimized instead of reappearing on screen. It does not take focus, and a tool window gets its taskbar button back. Quick windows that were showing keep their state.

## [1.17.1] - 2026-11-24

### Fixed
- Win chords on a modifier, such as CapsLock+Win+1 for `taskbar.activate`, now work while a remote session or virtual desktop window has focus. Before, the client took the Win key first, so hotkit saw CapsLock+1 and switched layers instead.

## [1.17.0] - 2026-11-24

### Changed
- The config file is `config.json` again; 1.16.0's switch to `config.jsonc` is reverted. The `"$schema"` link to `./config.schema.json` already keeps VS Code from flagging comments and trailing commas. If you renamed your config to `config.jsonc`, rename it back to `config.json`.

## [1.16.0] - 2026-11-24

### Changed
- The config file is now `config.jsonc`, so editors open it as JSON with comments and stop flagging its comments and trailing commas as errors, whether or not they load the schema. An existing `config.json` keeps working while there is no `config.jsonc`; rename it to switch. The running app follows the rename, and lists a config problem if both files exist.

## [1.15.5] - 2026-11-24

### Fixed
- `taskView.open` now opens Task View from any app. Before, it worked only while the desktop, taskbar or Start menu had focus, because Windows ignored the request from the background.

## [1.15.4] - 2026-11-23

### Fixed
- Quick window toggle, cycle and show all now skip windows hotkit can't manage, such as an app window running as administrator while hotkit is not, instead of failing with "Could not mark the new window for recovery."

## [1.15.3] - 2026-11-22

### Fixed
- `--check`, `--list-actions`, `--sync-plugins` and test runs no longer flash a tray icon while they run. Only a normal hotkit run shows the icon.

## [1.15.2] - 2026-11-22

### Fixed
- When an update can't fast-forward, the message now says what to do: switch to main when the folder is on another branch and main can take the update (the branch keeps its commits), or rebase local commits onto the release. When the branch is already ahead of the release, it says so instead of reporting a problem.

## [1.15.1] - 2026-11-19

### Fixed
- When an update can't install because the hotkit folder is on a branch other than main, the message now names the branch, instead of only saying the folder has commits the release doesn't have.

## [1.15.0] - 2026-11-19

### Changed
- In remote session windows, hotkit no longer lifts a forced CapsLock state, which could leave CapsLock on. Instead, a modifier with the new `remoteKey` option (for example `"caps": { "key": "CapsLock", "remoteKey": "F18" }`) is passed on as that key, and the remote hotkit treats it as the modifier. Without `remoteKey`, CapsLock combinations no longer reach the remote machine.
- hotkit now keeps its keyboard hook ahead of Remote Desktop's for as long as a remote session window is active, not only right after activation, so whether a key is handled locally or remotely no longer varies.

## [1.14.0] - 2026-11-19

### Added
- `settings.remoteWindows` lists remote session clients such as Remote Desktop. In their windows your local bindings keep working, and keys no local binding takes (for example CapsLock combinations unbound on the current layer) reach the remote machine and the hotkit running there. hotkit stays ahead of Remote Desktop's keyboard hook, so the CapsLock layer no longer sticks on after switching to a session, and a forced CapsLock state no longer swallows CapsLock there.
- Bindings accept `"yieldToRemote": true` to leave their keys to the remote machine while a remote session window is active.

## [1.13.0] - 2026-11-19

### Changed
- hotkit now keeps a copy of the schema next to your config (`config.schema.json`, refreshed on each version change), and the example config points `"$schema"` at `./config.schema.json`. VS Code loads it without asking you to trust a web domain, and it always matches the installed version. Change `"$schema"` in your config to `./config.schema.json` to use it.

## [1.12.1] - 2026-11-17

### Fixed
- VS Code no longer marks the comments and trailing commas in `config.json` as errors: the schema now declares them allowed, and the example config links the published schema (its relative link broke once the file was copied to the config folder).

## [1.12.0] - 2026-11-14

### Added
- hotkit checks GitHub for new releases. *Check for Updates* in the tray checks right away and becomes *Update to vX.Y.Z* when one is out; installing fast-forwards your git clone to the release tag and restarts hotkit. It refuses, with the reason in a toast, when the clone has uncommitted changes, is not on a branch, or has commits the release lacks. `settings.updates` turns checks off (`check`), installs automatically once you're idle (`apply`: `auto`), and sets the interval and repository. New actions: `app.checkForUpdates`, `app.update`.

## [1.11.0] - 2026-11-14

### Added
- Shortcuts no longer fire on keystrokes that other programs simulate, such as a dictation tool's paste, a remote-access client's injected keys, or another script. hotkit installs its own low-level keyboard hook that tells simulated keys from typed ones; the keys still reach the focused app. Set `"allowSimulated": true` on bindings that a program is meant to trigger (mouse button utilities, keys sent from remote machines), or `settings.ignoreSimulatedKeys` to `false` to turn it off.

### Changed
- The 1.10.2 pause of CapsLock shortcuts after dictation stops is gone; simulated keys are now ignored instead, which covers that case and any other program.

## [1.10.2] - 2026-11-14

### Fixed
- After a hold or press-then-next-key binding ends, a modifier key that is still held (such as CapsLock after letting go of Space) no longer fires its other bindings until it is released. A dictation tool's Ctrl+V paste then reaches the app even when Ctrl is still held too, instead of firing Caps+Ctrl+V.

## [1.10.1] - 2026-11-14

### Fixed
- A binding on a held modifier key (for example CapsLock) now fires only when its Ctrl, Shift, Alt, or Win keys are physically pressed. Keys another program injects while CapsLock is held, such as a dictation tool pasting with Ctrl+V, reach the app instead of firing Caps+Ctrl+V.

## [1.10.0] - 2026-11-14

### Added
- Press-then-next-key bindings: `onNextKey` runs an action on the next press of any other key and consumes that key, so the focused app never sees it. `onCancel` runs instead when that key is Escape. Modifier keys alone don't end it, and keys still held from the chord count only after they are released.
- `exclusive` names a set of hold and press-then-next-key bindings of which only one can be active: pressing another while one is active stops the active one instead of starting a second.

### Changed
- A press-and-hold binding (`onRelease`) now also ends when its modifier key (for example CapsLock) is released, whichever of the two keys comes up first. Key repeat stays swallowed until the key itself is released.

## [1.9.1] - 2026-11-14

### Fixed
- Keep Unlocked no longer leaves the screen saver (and its lock) off when hotkit is killed or crashes. Windows keeps the pause for the rest of the sign-in session, so a small guard process now turns the screen saver back on as soon as hotkit's process ends, and the next start repairs it if the guard is gone too. If the guard can't start, Keep Unlocked is refused instead.

## [1.9.0] - 2026-11-14

### Changed
- New tray icon: a steel-blue keycap with a soft-amber lightning bolt, replacing the four-key tile. The README and social wordmarks use JetBrains Mono Medium, bundled under the SIL Open Font License.
- The stay-awake warning badge is now a muted coral circle with a near-white "!" and a dark outline in the top-right corner, so it stands out on the new icon.

## [1.8.0] - 2026-11-14

### Added
- Layers: switchable sets of bindings, one active at a time. Define them under `layers` and give a binding `"layer": "<name>"` (or a list) to limit it to those layers; bindings without one work on every layer, and a layer binding overrides an every-layer binding on the same keys. Switching (`layer.activate`, `layer.next`, `layer.previous`, or tray › *Layer*) shows a toast and is remembered across restarts. The shortcut overlay shows the active layer's shortcuts, with a Layer column and an *All layers* option.
- `taskbar.activate` passes a held Win key through, so it can be bound to Win+<n> itself (e.g. `"*#1"` with the CapsLock modifier) and keep Windows' behavior of stepping through windows while Win is held.
- `tools/probe.py` runs throwaway AutoHotkey code headlessly, with warnings and errors in its output.
- A documented release process (`RELEASING.md`): `tools/release.py prepare` bumps the version and changelog, and merging the bump to `main` publishes the tag and GitHub Release automatically. Lint rule `REL001` keeps the version, changelog and tags in agreement.
- Test and tool runs now close any dialog a script opens and report its text (`dialog: ...`, exit code 125) instead of leaving it on screen.

### Changed
- Held-key layers are now called modifiers: define them under `modifiers` and name them in a binding with `modifier`. The old `layers` / `layer` form (a layer with a `key`) still works and is reported as a config problem to migrate.

## [1.7.0] - 2026-11-14

### Added
- The tray icon shows an amber warning badge while Keep Awake, Keep Screen On or Keep Unlocked is on. It works with a custom `tray.icon` too.

## [1.6.0] - 2026-11-14

### Added
- Time limits for Keep Awake, Keep Screen On and Keep Unlocked. Each toggle's tray submenu offers 30 minutes to 8 hours, and the `.on` and `.toggle` actions take an optional number of minutes. The tooltip and toast show the end time, and limits survive config reloads.
- Tray › Stay Awake › Turn All Off.

### Changed
- Clearer stay-awake wording in toasts, the tooltip, error messages and action descriptions.

### Fixed
- Unit tests no longer show an error dialog when a class fails to initialize; the error goes to the test output.

## [1.5.1] - 2026-11-14

### Changed
- The README wordmark now uses squarer, terminal-style monospaced letters with square stroke ends.
- Icon corner radii are now proportional to each box (20% of its shorter side), so the outer tile is rounder than its keys in proportion to its size.

## [1.5.0] - 2026-11-14

### Changed
- The tray icon's outer tile now uses the same corner radius as its four keys.
- The README logo's "hotkit" wordmark is now truly monospaced: every letter has the same advance width, with coding-font forms for narrow letters.

## [1.4.0] - 2026-11-14

### Added
- Stay-awake toggles (tray › Actions › Stay Awake, or the `power.*` actions): Keep Awake (no sleep), Keep Screen On, and Keep Unlocked (screen on and your own screen saver paused). All start off, show in the tray tooltip while on, survive config reloads, and use standard Windows power requests. Keep Unlocked refuses to turn on when a policy enforces a lock. Read the security notes in `docs/stay-awake.md` first.
- `monitors.off` action: turns all monitors off, and works while Keep Screen On or Keep Unlocked is on.
- Modules can define `BeforeRestart()` to hand state to the process that replaces them on a reload, and `Tray.AddStatus` adds text to the tray tooltip.

## [1.3.0] - 2026-11-14

### Changed
- New tray icon: a compact tile of four keys with one accent key, replacing the two staggered keys, which left the icon looking half empty. The README logo and social preview are redrawn to match, with a tighter crop.

## [1.2.0] - 2026-11-14

### Added
- hotkit now has its own tray icon (`assets/hotkit.ico`, two staggered keys in muted sage and dusty blue) instead of the AutoHotkey icon.
- README logo with light and dark variants, plus a social preview image, generated by `tools/make_brand.py`.
- `tray.icon` config option: use your own icon file, or an icon from a `.dll`/`.exe` with `{ "file": ..., "index": ... }`. An icon that can't be used falls back to the default and is listed as a config problem.

## [1.1.0] - 2026-11-08

### Fixed
- Saving `config.json` could restart the app while the file was half written and show a "Could not load config" dialog. Reloads now wait for the file to settle, and a config that doesn't parse is reported in a toast while the app keeps its previous config.
- `app.toggle` with several windows raised a different one on each show; it now returns to the window focused last.
- Cloaking checks no longer fail without DWM (e.g. under Wine).
- A hidden quick window now reappears when activated another way (taskbar button, Alt+Tab) instead of staying invisible.
- `quickWindow.toggle` failed with "Target window not found" when the app was running but its window was closed to the tray; it now runs the launch command and brings that window back.

### Added
- `taskbar.activate` action: Win+<n> for taskbar slot n, bindable to any key (e.g. Caps+1..0). When a full-screen window has focus it focuses the desktop first, so the keystroke reaches Windows instead of the app. On a layer, Win stays held while the layer key is held, so repeated presses step through an app's windows like holding Win does. Held Shift/Ctrl/Alt pass through (Win+Shift+<n> new instance, Win+Ctrl+<n> last active window, Win+Alt+<n> jump list); bind with a `*` prefix (e.g. `"*1"`) so the layer binding fires with them.
- `window.sendBackward`, `window.sendToBack`, `window.bringForward`, `window.bringToFront`: restack the active window without minimizing it or taking focus from it. Stepping skips windows it doesn't overlap, and always-on-top windows stay in their own layer.
- `window.cycleNext` / `window.cyclePrevious`: Alt+Tab-style focus cycling through on-screen windows. Bound on a layer, the window order is kept while the layer key is held, so each press only raises and focuses the selected window and puts the previous selection back.
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
