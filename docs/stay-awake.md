# Stay awake and monitors off

The `power` module adds three independent toggles and a monitors-off action.
Every toggle starts **off**, is shown with a check mark under tray ›
*Actions* › *Stay Awake*, and is named in the tray tooltip while it is on
(for example `hotkit 1.6.0: Keep Unlocked until 2:30 AM`).

| Toggle | What it does | Actions |
| --- | --- | --- |
| Keep Awake | The PC doesn't go to sleep. The screen can still turn off. | `power.keepAwake.toggle` / `.on` / `.off` |
| Keep Screen On | The screen stays on, and the PC stays awake. | `power.keepScreenOn.toggle` / `.on` / `.off` |
| Keep Unlocked | Keep Screen On, and your own screen saver is paused, so an idle session doesn't lock. | `power.keepUnlocked.toggle` / `.on` / `.off` |

`power.allOff` turns all three off. `monitors.off` turns every monitor off;
any key press or mouse movement turns them back on.

## Time limits

Each toggle can run for a set time and then turn itself off, like the
PowerToys Awake timer.

- **Tray:** each toggle has a submenu with *Off*, *On (no time limit)*, and
  *For 30 minutes*, *1 hour*, *2 hours*, *4 hours* or *8 hours*.
- **Actions:** pass a number of minutes to `.on` or `.toggle`, for example
  `{ "action": "power.keepUnlocked.on", "args": [90] }`. Without it, the toggle
  stays on until you turn it off.
- The tray tooltip and the toast show the end time, and another toast says
  when the toggle turns off. Choosing again replaces the old limit.

## Security

> [!WARNING]
> **Keep Unlocked leaves your signed-in session open to anyone who can reach
> the keyboard, mouse or a remote session.** Use it only on a PC you control,
> in a place you trust, and turn it off when you're done. hotkit shows a
> warning toast each time you turn it on.

- Use a time limit when you can, so Keep Unlocked can't be left on by
  mistake.
- Turning the monitors off (`monitors.off`) does not lock the PC. Press
  Win+L if you want it locked.
- hotkit does not get around locks someone else enforces. If Group Policy or
  MDM sets a machine inactivity limit (`InactivityTimeoutSecs`, or the
  DeviceLock `MaxInactivityTimeDeviceLock` policy) or a forced screen saver,
  Keep Unlocked refuses to turn on and says why; Keep Screen On and Keep Awake
  still work. hotkit never sends simulated key presses or mouse movement.
- Some locks are outside hotkit's reach and stay in effect: Dynamic Lock
  (locks when your phone leaves), smart-card removal, and sign-in after the
  PC wakes from sleep if something else puts it to sleep.

## How it works

- Keep Awake and Keep Screen On call `SetThreadExecutionState` with
  `ES_CONTINUOUS | ES_SYSTEM_REQUIRED` (plus `ES_DISPLAY_REQUIRED` for the
  screen), the same documented call PowerToys Awake uses. `powercfg
  /requests` (from an elevated prompt) lists hotkit while one is on. Windows
  drops the request automatically when hotkit exits.
- Keep Unlocked also pauses your screen saver with
  `SystemParametersInfo(SPI_SETSCREENSAVEACTIVE)` for the current session only.
  The setting in the registry is not changed, and hotkit turns the screen saver
  back on when you turn Keep Unlocked off or exit hotkit. If hotkit is killed,
  the screen saver stays paused until you sign out.
- `monitors.off` waits about half a second (so releasing the hotkey doesn't
  wake the screens), then sends `WM_SYSCOMMAND` / `SC_MONITORPOWER`. While the
  monitors are off, hotkit drops its screen-on request and only keeps the PC
  awake; the first input after that brings the screen-on request back. On PCs
  with Modern Standby, Windows may enter standby when the screens go off
  regardless; check with `powercfg /a`.

## Reloads and restarts

A config reload (saving `config.json`, `app.reload`, or tray › *Reload
Script*) keeps the toggles that were on, with their time limits. Exiting
hotkit, or starting it fresh, starts with everything off.

## Example bindings

```jsonc
"bindings": [
  { "keys": "#!u", "action": "power.keepUnlocked.toggle", "description": "Keep unlocked" },
  { "keys": "#!+u", "action": "power.keepUnlocked.on", "args": [480], "description": "Keep unlocked for 8 hours" },
  { "keys": "#!s", "action": "power.keepScreenOn.toggle", "description": "Keep screen on" },
  { "keys": "#!m", "action": "monitors.off", "description": "Monitors off" }
]
```

Set `"modules": { "power": { "enabled": false } }` to remove the actions and
the tray menu.
