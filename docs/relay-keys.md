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

Relay keys avoid the first two problems. The local machine never has to guess
which side a key is meant for: you decide per shortcut and send an
unambiguous key into the session. They don't help with the third, because the
local shortcut that sends the relay key must reach hotkit first. Before you
start, focus the session window and press a local shortcut that does
something visible. If it doesn't fire, change the client's keyboard setting
or use the client in a window, then try again.

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

Pick keys that nothing on either machine already uses: no binding, and no
modifier's `remoteKey`. F13 to F24 give 12 keys, and each combines with Ctrl,
Shift, and Alt for 96 in total. Write the
assignments down in one table and keep it the same in both configs:

| Shortcut you press (local) | Relay key | Action on the inner machine |
| --- | --- | --- |
| CapsLock+K | `F15` | Open the browser |
| CapsLock+Shift+K | `+F15` | Cycle browser windows |
| CapsLock+J | `F16` | Toggle the terminal |

### 2. Find the session window

Bindings on the local machine only send relay keys while the session window
is active. Find a WinTitle that matches it, for example with AutoHotkey's
Window Spy. Some examples:

| Client | WinTitle |
| --- | --- |
| Remote Desktop | `ahk_class TscShellContainerClass ahk_exe mstsc.exe` |
| Hyper-V console | `ahk_exe vmconnect.exe` |
| VNC viewer | `ahk_exe vncviewer.exe` |

### 3. Send relay keys from the local machine

Add one `send` binding per shortcut, limited to the session window with
`whenActive`. The examples use the `caps` modifier and layer `1` from the
example config. Use your own names, or leave out `layer` if you don't use
layers:

```jsonc
{ "layer": "1", "modifier": "caps", "keys": "K", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["{F15}"], "description": "Session: browser" },
{ "layer": "1", "modifier": "caps", "keys": "+K", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["+{F15}"], "description": "Session: next browser window" },
```

Outside the session window these bindings do nothing, and CapsLock+K keeps
its normal local meaning, if it has one.

To reuse a shortcut that already has a local binding, list the session
version above the local one. Bindings that differ only in `whenActive` don't
conflict, and when both match, the one listed first wins, so the session
version takes over only while the session window is active. Order decides
only between bindings of the same kind: all bindings limited to layers come
before bindings that apply on every layer, wherever they are listed. So if
the local binding has a `layer`, give the session version a `layer` too.

### 4. Bind the relay keys on the inner machine

In the inner machine's config, bind each relay key and set `allowSimulated`.
The actions are ordinary hotkit actions. This example toggles an app defined
under `apps`:

```jsonc
"apps": {
  "browser": { "name": "Browser", "run": "msedge.exe", "match": "ahk_exe msedge.exe" }
},
"bindings": [
  { "keys": "F15", "allowSimulated": true, "action": "app.toggle", "args": ["browser"] },
  { "keys": "+F15", "allowSimulated": true, "action": "app.cycle", "args": ["browser"] }
]
```

hotkit ignores keys that programs simulate unless the binding allows them
(see [Simulated keys](configuration.md#simulated-keys)). Some clients deliver
forwarded keys as simulated input, so allow them on every relay binding.

### 5. Test one key end to end

Before you add more, check each hop on its own:

1. **The local binding fires in the session window.** Temporarily change
   only the local relay binding's action to `"osd.toggle"` (no `args`),
   keeping its `whenActive`. Focus the session window and press the
   shortcut: the local shortcut overlay should open. If it doesn't, fix the
   WinTitle. Then put the `send` action back.
2. **The inner binding fires.** On the inner machine, change only the action
   of the `F15` binding to `"sendText"` with `["relay ok"]`, keeping
   `allowSimulated`. Trigger F15 on the inner machine itself with a temporary
   binding such as
   `{ "keys": "F9", "action": "hotkey.trigger", "args": ["F15"] }` while a
   text editor is focused: "relay ok" should appear.
3. **The key arrives.** Focus the text editor in the session and press the
   local shortcut. If "relay ok" appears, restore the inner action and add
   the rest of the table.

If steps 1 and 2 work but nothing arrives in step 3, the client drops that
key. Use a combination of normal
keys instead, such as Ctrl+Shift+Alt plus a letter. Send it with
`{Ctrl down}{Shift down}{Alt down}k{Alt up}{Shift up}{Ctrl up}` and bind
`^+!k` on the inner machine.

## Handing the whole keyboard to the session

Sometimes you want every CapsLock shortcut to go to the inner machine, not
only the ones in your relay table. Use a layer for this:

1. Define a second layer: `"layers": ["1", "2"]`.
2. Keep the layer keys on every layer by leaving out `layer`:
   `{ "modifier": "caps", "keys": "1", "action": "layer.activate", "args": ["1"] }`
   and the same for `2`.
3. Limit the local shortcuts that should yield to the session to layer 1 with
   `"layer": "1"`. Any binding without `layer` still fires on layer 2.
4. Put the relay bindings on both layers, `"layer": ["1", "2"]`, or on layer 2
   only if you want them just there.
5. Switch to layer 2 (CapsLock+2) before working in the session, and back to
   layer 1 (CapsLock+1) when you leave.

On layer 2, every key without a binding passes through to the session. This
frees keys, not the CapsLock modifier: when CapsLock is forced off it is
still swallowed, so CapsLock+J reaches the session as a plain J (unless you
use the automatic `remoteKey` forwarding described under
[Remote sessions](configuration.md#remote-sessions)). To trigger a
CapsLock binding on the inner machine, add a relay key for it.

## Relay keys as a modifier

Instead of one relay key per shortcut, one relay key can stand in for the
CapsLock modifier. The local machine holds it down around the key you
pressed, and the inner machine treats it as a modifier, like CapsLock. The
inner config then reads like the local one, and Ctrl, Shift, and Alt
variants carry over.

On the local machine, send the relay key with the chord inside it. Here
layer 2 hands CapsLock shortcuts to the session. Keep `whenActive`: a layer
stays active when focus leaves the session window, and Ctrl+Q sent to a
local app may quit it.

```jsonc
{ "layer": "2", "modifier": "caps", "keys": "Q", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["{F13 down}q{F13 up}"], "description": "Session: browser" },
{ "layer": "2", "modifier": "caps", "keys": "<^Q", "whenActive": "ahk_exe vncviewer.exe",
  "action": "send", "args": ["{F13 down}^q{F13 up}"], "description": "Session: new browser window" },
```

On the inner machine, define the relay key as a modifier and set
`allowSimulated` on its bindings:

```jsonc
"modifiers": { "relay": { "key": "F13", "label": "F13" } },
"bindings": [
  { "modifier": "relay", "keys": "Q", "allowSimulated": true, "action": "app.toggle", "args": ["browser"] },
  { "modifier": "relay", "keys": "<^Q", "allowSimulated": true, "action": "app.launch", "args": ["browser"] }
]
```

With `allowSimulated`, a modifier binding accepts a relay key and Ctrl,
Shift, or Alt that the client injects, not just keys typed on the inner
machine's keyboard. Leave Win out of relayed chords: clients often keep it
for themselves.

For a machine nested one level deeper, use another relay key, such as F14,
on another local layer. The middle machine must leave both F14 and the keys
inside the chord free: with no binding on F14, and its own bindings on those
keys limited to its F13 modifier, the chord passes through it to the nested
session.

## Deeper nesting

The same technique works at every level. Each machine relays the keys meant
for the level below it:

- The outer machine sends `F15` while the first session is active.
- The middle machine binds `F15` and, while its own nested session window is
  active, sends a different key instead of acting on it:
  `{ "keys": "F15", "allowSimulated": true, "whenActive": "<nested session window>", "action": "send", "args": ["^{F15}"] }`.
- The innermost machine binds `^F15`:
  `{ "keys": "^F15", "allowSimulated": true, "action": "..." }`.

In `send` arguments, key names such as F15 go in braces (`{F15}`, `^{F15}`).
In `keys`, they don't (`F15`, `^F15`).

Give each level its own relay keys, for example plain F13 to F24 for the
first level and Ctrl+F13 to Ctrl+F24 for the second. That way a key that
passes through a level by mistake can't trigger the wrong action.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Nothing happens on the inner machine | The client drops the relay key, or the binding lacks `allowSimulated` | Run the hop-by-hop test in step 5. Add `allowSimulated`. |
| The local action runs instead | The local binding is listed above the session binding, or is limited to layers while the session binding isn't | Give both the same `layer` setting and list the `whenActive` binding first. |
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
