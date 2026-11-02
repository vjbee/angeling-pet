# Angeling Pet

A floating macOS desktop pet (Swift/AppKit) that shows Claude Code session status, rings reminders that it also adds to Calendar, and shows unread counts for LINE and Discord. Distributed through GitHub Releases with a one-line installer.

## Layout

| Path | What |
|---|---|
| `src/main.swift` | The whole app, one file. Sections (`// MARK:`): sprite sheet, Bomber characters, session state, Focus (jump to window), LINE, Discord, Updates, Reminders, usage limits (statusLine wrapper), rows/bubble, pet view, controller, hotkeys, app entry plus debug modes |
| `hooks/angeling-hook.sh` | Claude Code hook (11 events). Writes `~/.claude/angeling-pet/state/<session>.json`, with a per-session mkdir lock and mktemp+mv writes |
| `install.sh` / `uninstall.sh` | Installer: prebuilt app from a bundle, or builds from source. The Claude hook is optional |
| `get.sh` | One-line installer: downloads `Angeling.zip` from the latest release and runs its `install.sh` |
| `scripts/build.sh` | `swiftc` build into an `.app`. Version comes from `ANGELING_VERSION`, then the latest git tag, then `dev` |
| `scripts/package.sh <ver>` | Universal (arm64+x86_64) app plus release files in `dist/` |
| `scripts/import-characters.py <zip>` | Builds `assets/characters/` (sheets + `characters.json` frame table) from the Bomber character pack |
| `scripts/import-pet.swift <sheet> <id> "<Name>"` | Fits a generated sheet onto the Codex v2 grid as `assets/pets/<id>/` (Bee Husky came from `~/Downloads/huskey.png`) |
| `scripts/fetch-assets.sh` | Fills `assets/` from: a local Codex pet, then the latest release, then irowiki/myinstants |
| `docs/` | User guide in **Thai**. `docs/README.md` is the index; every page ends with a link back to it |

Runtime files: `~/Applications/Angeling.app`, `~/.claude/angeling-pet/` (hook, artwork, `state/`, `reminders.json`, `update.log`, and with limits on: `statusline.sh`, `statusline-orig.*`, `limits.json`), LaunchAgent `local.angeling.pet`, and UserDefaults domain `local.angeling.pet`.

## Build and check

```bash
./scripts/build.sh "$PWD/build/Angeling.app"      # compile check, doesn't touch the installed app
./scripts/build.sh && pkill -x Angeling; open ~/Applications/Angeling.app   # install locally
```

Screen recording isn't permitted, so verify UI with snapshot mode, which renders the window to a PNG and quits:

```bash
ANGELING_SNAPSHOT=/path/out.png build/Angeling.app/Contents/MacOS/Angeling
```

Fakes for snapshots are listed in `docs/Development.md`:
- `ANGELING_EXPANDED`, `ANGELING_LIMITS`, `ANGELING_LIMIT_MODE`, `ANGELING_LIMIT_PLACE`, `ANGELING_HIDE_ACTIVITY`, `ANGELING_HOVER`, `ANGELING_EMOTE`, `ANGELING_FORM`
- `ANGELING_LINE_UNREAD`, `ANGELING_DISCORD_UNREAD`, `ANGELING_REMINDERS`, `ANGELING_STATE_DIR`, `ANGELING_THEME`
- `ANGELING_CHARACTER`, `ANGELING_ANIM`
- `ANGELING_FAKE_VERSION`, `ANGELING_LATEST_VERSION`, `ANGELING_UPDATE_NOW`, `ANGELING_UPDATE_CMD`

Installer tests go in a throwaway HOME:
- `env -i HOME=<tmp> PATH=/usr/bin:/bin:/usr/sbin:/sbin ANGELING_NO_LAUNCH=1 bash get.sh --no-login`
- Always pass `--no-login`; otherwise `launchctl` replaces the real `local.angeling.pet` login item.
- The installer's `pkill` closes the user's real Angeling, so reopen it afterwards.
- Never run `defaults delete local.angeling.pet` or `uninstall.sh --purge` in tests: `defaults` ignores HOME and wipes the user's real prefs.

## Rules

- **Git**: `main` is protected, so all changes go through a branch and a PR. Commits use `k.chaipaphat@gmail.com`. Merge with `gh pr merge <n> --rebase --delete-branch`: squash makes GitHub author the commit with the noreply address, and `--author-email` is rejected. Merge or release only when the user says so.
- **Releases**: friends install and update from the latest release, not from `main`. Release steps:
  1. `./scripts/package.sh X.Y.Z`
  2. `gh release create vX.Y.Z dist/* --target main …` (every release must attach all of `dist/*`)
  3. verify with the real one-liner in a throwaway HOME

  Running apps notice a new release within 6 h.
- **Artwork** (Angeling sprite sheet, Ragnarok emotes, level-up sound) is © Gravity. It is never committed (see `.gitignore`); it ships only as release assets. The Bomber characters (`assets/characters/`, built by `scripts/import-characters.py`) follow the same rule and ship as `characters.zip`; extra Codex pets (`assets/pets/`, e.g. Bee Husky) ship as `pets.zip`.
- **Privacy**: LINE and Discord show **counts only**, read from each app's Dock badge via `lsappinfo`. Do not read message contents or the Notification Center database, and do not ask for Full Disk Access. The user decided this explicitly.
- **UI text** is Thai and **code comments** are English, matching the existing style. Keep `main.swift` as one file and follow its section layout.
- **Signing** is ad-hoc. macOS privacy grants (Calendar) are tied to the exact build, so expect re-prompts after updates. A fixed-DR signing experiment did not make grants persist and was reverted.
- **Self-update**: the installer must close its own parent app, so `install.sh` uses `pkill -a` (macOS `pkill` skips ancestors by default). Keep that flag.
- **Docs**: when behaviour changes, update `README.md` and the matching `docs/*.md` page, and check that every relative `.md` link resolves.
