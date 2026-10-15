# Contributing

This is a personal toolkit shared in the open. Read
[docs/philosophy.md](docs/philosophy.md) first: changes that make the engine
more general are welcome; one person's shortcuts or apps belong in their own
config.

## Before opening a PR

1. Open an issue for anything larger than a fix, so we can agree it fits.
2. Keep changes focused; one concern per PR.
3. Run `python tools/test.py all` (see [docs/testing.md](docs/testing.md)).
4. New logic comes with unit tests; new actions need a `description` and
   `params`, and `python tools/gen_docs.py` to refresh `docs/actions.md`.
5. Never commit personal data: names, usernames, paths under `C:\Users\<you>`,
   employer names, URLs to private resources. Put your own terms in a local
   `.private-terms` file (one per line, git-ignored) and lint will catch them.

## Style

- AutoHotkey v2 only: `#Requires AutoHotkey v2.0` at the top of every file.
- No copyright headers in source files.
- Pure static methods for decisions; thin wrappers around Win32 calls.
- Local variable names must not match class names (AutoHotkey names are
  case-insensitive: a local `map` hides `Map`).
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Scope

Out of scope: anything whose purpose is to get around restrictions set by an
employer, a remote desktop/VDI provider, or another system owner.
