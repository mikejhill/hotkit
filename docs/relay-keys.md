# Hotkeys inside remote and virtual sessions

A remote desktop client, a virtual machine console, or a virtual desktop
viewer forwards your keystrokes to another machine. When that machine runs
hotkit too, its shortcuts and the ones on your local machine compete for the
same keys. This playbook shows how to make shortcuts on the inner machine
work reliably, at any depth of nesting, using *relay keys*.

## Why shortcuts get lost

Every keystroke goes through the low-level keyboard hooks on your local
machine before the session window sees it. Windows calls the most recently
installed hook first.

- **The local hotkit usually wins.** Its hook sees the key first. When a
  local binding matches, hotkit handles the key and the session never gets
  it. A key with no local binding passes through to the session.
- **A held modifier may never arrive.** With
  `"settings": { "keyboard": { "capsLock": "AlwaysOff" } }`, hotkit swallows
  CapsLock completely, so the inner machine never sees it held and its
  CapsLock bindings never fire.
- **Some clients take every key.** A full-screen client may install its own
  keyboard hook when its window gets focus, ahead of hotkit's. The client then
  forwards every key, including local shortcuts, and can swallow the release of
  a key that was down when it took over. Clients usually have a setting for
  where Windows key combinations apply. Check it if local shortcuts stop
  working only while the client is full screen.

Relay keys avoid all of this. The local machine never has to guess which side
a key is meant for. You decide per shortcut and send an unambiguous key into
the session.

## How relay keys work

1. You press a local shortcut, for example CapsLock+K, while the session
   window is active.
2. The local hotkit sends a *relay key* into the session, a key that no
   physical keyboard has, such as F15.
3. The client forwards F15 to the inner machine like any other key.
4. The hotkit on the inner machine has a binding on F15 and runs the action.

F13 to F24 suit this: they exist in Windows and in remote protocols, but
keyboards rarely have them, so nothing else reacts to them.

## Playbook

### 1. Choose relay keys

Pick keys that no binding on either machine already uses. F13 to F24 give 12
keys, and each combines with Ctrl, Shift, and Alt for 96 in total. Write the
assignments down in one table and keep it the same in both configs:

| Shortcut you press (local) | Relay key | Action on the inner machine |
| --- | --- | --- |
| CapsLock+K | `F15` | Open the browser |
| CapsLock+Shift+K | `+F15` | Cycle browser windows |
| CapsLock+J | `F16` | Toggle the terminal |

### 2. Find the session window

Bindings on the local machine only send relay keys while the session window
is active. Find a WinTitle that matches it, for example with AutoHotkey's
Window Spy:

```text
ahk_class TscShellContainerClass ahk_exe mstsc.exe   (Remote Desktop)
ahk_exe vmconnect.exe                                (Hyper-V console)
ahk_exe vncviewer.exe                                (VNC viewer)
```

### 3. Send relay keys from the local machine

Add one `send` binding per shortcut, limited to the session window with
`whenActive`:

```jsonc
{ "layer": "1", "modifier": "caps", "keys": "K", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["{F15}"], "description": "Session: browser" },
{ "layer": "1", "modifier": "caps", "keys": "+K", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["+{F15}"], "description": "Session: next browser window" },
```

Outside the session window these bindings do nothing, and CapsLock+K keeps
its normal local meaning, if it has one.

To reuse a shortcut that already has a local binding, add the session
version above the local one in your config. Bindings that differ only in
`whenActive` don't conflict. When both match, the one listed first wins, so
the session version takes over only while the session window is active.

### 4. Bind the relay keys on the inner machine

In the inner machine's config, bind each relay key and set `allowSimulated`:

```jsonc
{ "keys": "F15", "allowSimulated": true, "action": "app.toggle", "args": ["browser"] },
{ "keys": "+F15", "allowSimulated": true, "action": "app.cycle", "args": ["browser"] },
```

hotkit ignores keys that programs simulate unless the binding allows them
(see [Simulated keys](configuration.md#simulated-keys)). Some clients deliver
forwarded keys as simulated input, so allow them on every relay binding.

### 5. Test one key end to end

Before you add more, check that the client forwards the relay key:

1. On the inner machine, bind `F15` to something visible, such as
   `{ "action": "sendText", "args": ["relay ok"] }`, and focus a text editor.
2. On the local machine, focus the session window and press the shortcut.
3. If the text appears, add the rest of the table.

If nothing arrives, the client drops that key. Use a combination of normal
keys instead, such as Ctrl+Shift+Alt plus a letter. Send it with
`{Ctrl down}{Shift down}{Alt down}k{Alt up}{Shift up}{Ctrl up}` and bind
`^+!k` on the inner machine.

## Handing the whole keyboard to the session

Sometimes you want every CapsLock shortcut to go to the inner machine, not
only the ones in your relay table. Use a layer for this:

1. Define a layer, for example `"layers": ["1", "2"]`, and keep only the
   layer keys and the relay bindings on layer 2.
2. Switch to layer 2 (CapsLock+2) before working in the session, and back to
   layer 1 (CapsLock+1) when you leave.

On layer 2, every key without a binding passes through to the session.
CapsLock itself is still swallowed when it's forced off, so the relay keys
remain the way to reach the inner machine's CapsLock bindings.

## Deeper nesting

The same technique works at every level. Each machine relays the keys meant
for the level below it:

- The outer machine sends `F15` while the first session is active.
- The middle machine binds `F15` and, while its own nested session window is
  active, sends a different key, such as `^F15`, instead of acting on it.
- The innermost machine binds `^F15`.

Give each level its own relay keys, for example plain F13 to F24 for the
first level and Ctrl+F13 to Ctrl+F24 for the second. That way a key that
passes through a level by mistake can't trigger the wrong action.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Nothing happens on the inner machine | The client drops the relay key, or the binding lacks `allowSimulated` | Run the end-to-end test in step 5. Add `allowSimulated`. |
| The local action runs instead | The local binding is listed above the session binding | Move the `whenActive` binding above it. |
| The relay key fires outside the session | `whenActive` is missing or matches other windows | Narrow the WinTitle, for example with `ahk_class`. |
| Local shortcuts stop working only in full screen | The client's keyboard hook takes keys first | Check the client's setting for where Windows key combinations apply, or work in a window. |
| A modifier seems stuck after switching into the session | The client took over the keyboard while the key was held and kept its release | Press and release the modifier again. |

## Related

- [Configuration reference](configuration.md): `whenActive`, layers,
  modifiers, and `allowSimulated`.
- [Remote sessions](configuration.md#remote-sessions): `settings.remoteWindows`,
  an automatic alternative that re-installs hotkit's keyboard hook while a
  session window is active. Re-installing makes hotkit forget held keys, so
  relay keys are more predictable.
