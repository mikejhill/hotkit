# Plugins

A plugin is an `.ahk` file in `<config dir>\plugins\`. It is included at
startup like any other script, so it can use everything in `src/`. Use plugins
for code that is private or too specific for the repository.

Only top-level `*.ahk` files are loaded. Put helpers in a subfolder and include
them relative to the plugin:

```
plugins\
  Notes.ahk
  notes\NotesClient.ahk
```

## Minimal plugin

```ahk
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\notes\NotesClient.ahk

App.AddPlugin("notes", (settings) => NotesPlugin.Init(settings))

class NotesPlugin {
    static Init(settings) {
        folder := MapGet(settings, "folder", "~\Notes")
        ActionRegistry.Register("notes.today", (*) => NotesClient.OpenDaily(Paths.Expand(folder)),
            { module: "plugin:notes", description: "Open today's note" })
    }
}
```

```jsonc
// config.json
"plugins": { "notes": { "folder": "~\\Documents\\Notes" } },
"bindings": [ { "keys": "#n", "action": "notes.today" } ]
```

## API

| Call | When | Purpose |
| --- | --- | --- |
| `App.AddPlugin(name, init)` | file load | `init(settings)` runs during boot with the `plugins.<name>` map |
| `ActionRegistry.Register(id, fn, meta)` | in `init` | Add actions (`module: "plugin:<name>"` by convention) |
| `Bindings.Add(map, source)` | in `init` | Add a binding from code |
| `App.OnReady(fn)` | in `init` | Run after hotkeys are live |
| `App.Mode` | anywhere | `"run"`, `"check"`, or `"list-actions"`; start timers or background work only in `"run"` |
| `MapGet(map, key, default)`, `Paths.Expand(path)` | anywhere | Helpers |

Errors thrown from `init` are reported as config problems; the rest of the app
still starts. AutoHotkey resolves `#Include` before a script runs, so after
adding or removing a plugin, refresh the include list before validating:

```powershell
AutoHotkey64.exe src\Main.ahk --sync-plugins
AutoHotkey64.exe src\Main.ahk --check
```

`--check` reports a stale plugin list as a problem. The running app refreshes it
on its own. Adding or removing a plugin file restarts the app; editing one
needs *Reload* from the tray (or `app.reload`).

## Rules

- Do not use `#SingleInstance`, `Persistent`, or top-level hotkeys (`F1::`):
  register actions and let config bind them.
- Guard background work with `if (App.Mode = "run")` so `--check` stays fast and
  side-effect free.
