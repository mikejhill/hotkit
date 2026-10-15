# Philosophy

## Capability in the repository, intent in the config

The repository answers *what can be automated*: toggle an app, float a window,
dim a display, switch to the previous window. Your config answers *what you
want*: which app, which key, which window. Nothing in `src/` knows about a
particular person's apps, URLs, or employer. If a feature can only be described
with someone's specific setup, it belongs in their config or in a private plugin.

## Small, named actions

Every behavior is an action with an id (`brightness.increase`), a description,
and positional arguments. Keys, tray items, gestures, and plugins all refer to
actions by id. One registry means one place to list, document, test, and show in
the shortcut overlay.

## Fail loudly at load, never at keypress

Config is validated before any hotkey is registered: unknown actions, unknown
layers, conflicting keys, malformed gestures. Problems are reported in one list
(tray, `--check`, CI), and the rest of the config still loads. A broken binding
should never be discovered by pressing it.

## Respect the machine you are on

These scripts automate *your own* desktop. They are not a means to work around
controls set by an employer, a remote desktop or VDI provider, or any other
system owner. Features that only make sense for that purpose are out of scope.

## Boring, inspectable code

- Plain AutoHotkey v2, no build step, no dependencies beyond the interpreter.
- Pure functions for decisions (parsing, matching, math) so they can be unit tested;
  thin wrappers for Win32 calls.
- Every file is readable top to bottom; comments explain *why*.

## Personal, shared in the open

This is one person's toolkit. It is published because the engine is generally
useful, not as a product with a roadmap. Changes that make the engine more
general are welcome; changes that add one person's preferences belong in their
config.
