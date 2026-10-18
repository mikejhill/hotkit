# Example plugins

Three small, complete plugins to copy from. Each one is a top-level `.ahk`
file plus a helper folder of the same name with the logic that has no UI, so
it can be unit tested. See [docs/plugins.md](../../docs/plugins.md) for the API.

| Plugin | Actions | Shows |
| --- | --- | --- |
| [BreakReminder](BreakReminder.ahk) | `breakReminder.now`, `.togglePause`, `.status` | Settings with defaults, settings validation, a timer started only in `run` mode, `App.OnReady` |
| [QuickNote](QuickNote.ahk) | `quickNote.add [text]`, `quickNote.open` | An action with an optional parameter, `Paths.Expand`, writing a file |
| [Stopwatch](Stopwatch.ahk) | `stopwatch.toggle`, `.lap`, `.reset`, `.show` | State kept between actions, all settings optional |

## Try one

1. Copy the plugin file and its folder into `<config dir>\plugins\`
   (default `%USERPROFILE%\.config\hotkit\plugins\`), for example
   `Stopwatch.ahk` and `Stopwatch\`.
2. Merge its section of [config.example.jsonc](config.example.jsonc) into
   your `config.json`.
3. The running app picks up the new file and restarts. To check without
   running:

   ```powershell
   AutoHotkey64.exe src\Main.ahk --sync-plugins
   AutoHotkey64.exe src\Main.ahk --check
   ```

## Make your own

1. Copy the closest example and rename the file, folder, classes, plugin name
   and action prefix (`stopwatch.` → `myplugin.`).
2. Put decisions in the helper class as static methods that take plain values
   (pass `A_TickCount` in rather than reading it), and keep the plugin class a
   thin layer that reads settings, registers actions and shows UI.
3. Register actions; never define hotkeys in the plugin. Bind keys in config.
4. Start timers or background work only when `App.Mode = "run"`.

The repository's tests load these examples (`tests/unit/ExamplePlugins.Test.ahk`
and the integration stage of `tools/test.py`), so they stay working.
