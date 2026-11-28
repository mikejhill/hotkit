# Schedules

A schedule runs an action at set times, at a fixed interval, or when
something happens, such as Hotkit starting or the PC being locked. Any action
works, including `theme.set`, `brightness.set`, `run`, and actions that
plugins register.

```jsonc
"schedules": [
  // Dark theme at 7 PM. If the PC was asleep then, switch when it wakes.
  { "name": "evening", "cron": "0 19 * * *", "action": "theme.set", "args": ["dark"], "catchUp": true },
  { "name": "morning", "cron": "0 7 * * mon-fri", "action": "theme.set", "args": ["light"], "catchUp": true },

  // Set brightness whenever you come back to the PC.
  { "on": ["unlock", "resume"], "delay": "5s", "action": "brightness.set", "args": [70] },

  // A plugin's job every 30 minutes, only on one machine.
  { "every": "30m", "action": "myPlugin.sync", "machines": ["WORKPC"] }
]
```

A schedule needs `action` and at least one of `cron`, `every`, or `on`. It
runs whenever any of them fires.

| Field | Meaning |
| --- | --- |
| `action`, `args` | Action id and positional arguments ([actions.md](actions.md)) |
| `name` | Unique name for `schedule.run` and the status log. Defaults to `schedules[N]` |
| `cron` | A [cron expression](#cron-expressions) in local time, or a list of them |
| `every` | Run at this interval: `"90s"`, `"15m"`, `"2h"`, `"1d"`, `"1h30m"` (at most 24 days). The first run is one interval after Hotkit starts |
| `on` | An [event](#events), or a list of them |
| `delay` | Wait this long after an `on` event before running, such as `"30s"` after `startup` for the network to come up (at most 24 days). Not allowed with `exit` or `sleep` |
| `idleAfter` | For `idle` and `active`: how long without keyboard or mouse input counts as idle. Default `"10m"`, at least `"10s"` |
| `catchUp` | With `cron`: when a time passed unseen, because the PC was asleep or the clock jumped ahead, run once afterwards instead of skipping it. Default `false` |
| `machines` | Only use this schedule on these computers, by name (`hostname` in a terminal). Useful when one config syncs to several PCs |
| `description` | Your own note |
| `enabled` | `false` skips the schedule |

Problems, such as a bad cron field or an unknown action, appear with the
other config problems (tray › *Show Config Problems*, and `--check`). Each run
is written to the status log (`%LOCALAPPDATA%\hotkit\hotkit.log`).
`schedule.run` runs a schedule by name, so you can bind a key to try one out.

## Cron Expressions

Five fields, separated by spaces, in the PC's local time:

```text
┌ minute (0-59)
│ ┌ hour (0-23)
│ │ ┌ day of month (1-31)
│ │ │ ┌ month (1-12 or jan-dec)
│ │ │ │ ┌ day of week (0-7 or sun-sat; 0 and 7 are Sunday)
* * * * *
```

| Form | Example | Means |
| --- | --- | --- |
| `*` | `* * * * *` | Every minute |
| Number or name | `30 7 * * *` | 7:30 every day |
| Range | `0 9 * * mon-fri` | 9:00 on weekdays |
| List | `0 8,12,17 * * *` | 8:00, 12:00, and 17:00 |
| Step | `*/15 * * * *` | Every 15 minutes |
| Step over a range | `0 8-18/2 * * *` | Every two hours from 8:00 to 18:00 |
| Shorthand | `@hourly`, `@daily` (`@midnight`), `@weekly`, `@monthly`, `@yearly` (`@annually`) | |

As in classic cron, when both day fields are restricted, a day matches if
either one does: `0 12 1 * fri` runs at noon on the 1st and on every Friday.

Hotkit checks the schedule just after each minute starts. A time that never
happens, such as February 30, is reported as a problem. Times that pass while
the PC is asleep or Hotkit isn't running are skipped unless `catchUp` is set.
`catchUp` runs a missed schedule once, however many of its times passed, and
runs several missed schedules in the order their times fell, so the latest
wins. It covers only gaps while Hotkit is running: a run missed while Hotkit
was closed is not made up at the next start. Add `"on": "startup"`
when you need that.

## Events

| Event | When |
| --- | --- |
| `startup` | Hotkit starts. A reload is not a startup |
| `reload` | Hotkit restarts itself: *Reload Script*, `app.reload`, a config change, or an update |
| `exit` | Hotkit exits: tray › *Exit*, `app.exit`, sign-out, or shutdown. Not on reload, and not when the process is killed. Keep these actions quick |
| `lock` | The session is locked (Win+L, or the screen saver locks it) |
| `unlock` | The session is unlocked |
| `sleep` | The PC is going to sleep or hibernate. Windows waits only briefly, so keep these actions quick |
| `resume` | The PC wakes from sleep or hibernate |
| `idle` | No keyboard or mouse input for `idleAfter` |
| `active` | Input again after `idle` |
| `pluggedIn` | The PC switches from battery to AC power |
| `unplugged` | The PC switches from AC power to battery |
| `remoteConnect` | Someone connects to this session over Remote Desktop |
| `remoteDisconnect` | That Remote Desktop connection ends |

To run something on every start, reloads included, use
`"on": ["startup", "reload"]`. On PCs with Modern Standby, Windows may not
report every short sleep; `unlock` is usually the more reliable signal that
you are back.

## From a Plugin

A plugin can register an action and schedule it from config, or add the
schedule itself during `init`:

```ahk
App.AddPlugin("backup", (settings) => BackupPlugin.Init(settings))

class BackupPlugin {
    static Init(settings) {
        ActionRegistry.Register("backup.run", (*) => BackupPlugin.Run(),
            { module: "plugin:backup", description: "Back up my notes" })
        Schedules.Add(Map("name", "backup", "cron", MapGet(settings, "cron", "0 12 * * *"),
            "action", "backup.run"), "plugin:backup")
        Schedules.On("lock", (event) => BackupPlugin.Run())
    }
}
```

`Schedules.On(event, fn)` calls `fn(event)` for any event in the table above.
For `idle` and `active` it uses the default idle time of 10 minutes.
