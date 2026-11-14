# Releasing

A release is a version tag (`vX.Y.Z`) and a GitHub Release whose notes are
that version's `CHANGELOG.md` entries. hotkit is not published to a package
registry.

## How it works

- `App.Version` in `src/Core/App.ahk` is the single source of truth for the
  version. The app shows it in the tray and in toasts.
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
  Every user-visible change adds a line under `## [Unreleased]` in the same PR.
- When a push to `main` changes `App.Version` to a version that has no tag,
  the [Release workflow](.github/workflows/release.yml) creates the tag on
  that commit and publishes the GitHub Release. Every other push is a no-op.
- Lint rule `REL001` (`python tools/release.py check`) fails when
  `App.Version`, the newest changelog heading and the tags disagree, when a
  branch is behind the latest tag, or when a released version's notes are
  edited to add entries.

Nobody tags or creates releases by hand. Version tags are immutable.

## Version numbers

Versions follow [Semantic Versioning](https://semver.org/). For hotkit, the
public interface is the config format, action names and parameters,
command-line flags and the plugin API.

| Bump | When | Changelog subsection |
| --- | --- | --- |
| Major | A user has to change their config, bindings or plugins: an action, parameter, config key or flag is removed or renamed, or a default changes incompatibly | `### Removed`, or an entry starting with `**Breaking:**` |
| Minor | New features, actions or options, or a visible change in behavior | `### Added`, `### Changed`, `### Deprecated` |
| Patch | Bug fixes and security fixes only | `### Fixed`, `### Security` |

`prepare` infers the bump from these subsections. Override it with `--bump`
when the inference is wrong, for example `--bump patch` for a purely cosmetic
`Changed` entry.

## Cutting a release

Release whenever `[Unreleased]` has entries worth shipping. Sessions may
release without asking.

1. Make sure your branch is up to date with `main`.
2. Run the prepare step. It fetches tags, picks the next version and rewrites
   `CHANGELOG.md` and `src/Core/App.ahk`:

   ```powershell
   python tools\release.py prepare            # or --bump patch|minor|major, or --version X.Y.Z
   ```

3. Commit the two files as `chore: release vX.Y.Z`, either as the last commit
   of the feature PR or in a PR of its own, and merge it through the normal PR
   flow (CI and review).
4. The Release workflow publishes `vX.Y.Z` within a minute of the merge.
   Check it with `gh release view vX.Y.Z`.

## Concurrent releases

Two branches can prepare the same version. Whichever merges first wins; the
other then fails `REL001` in CI (its notes differ from the released ones) or
conflicts with `main`. To fix it, update the branch from `main`, revert its
`CHANGELOG.md` and `App.ahk` release edits so the entries sit under
`[Unreleased]` again, and rerun `prepare`. Run `prepare` as late as possible
to make this rare.

## Other commands

```powershell
python tools\release.py check              # same as lint rule REL001
python tools\release.py notes [X.Y.Z]      # print a version's release notes
python tools\release.py publish --dry-run  # show what the workflow would publish
```

If the workflow fails after a merge, fix the cause and rerun it from the
Actions tab (it also has a manual trigger). `publish` is idempotent.
