# Angeling Pet

A floating macOS desktop pet. Angeling, a little pink angel from Ragnarok Online, sits in a corner of your screen and:

- **reminds you** of things at the time you set (with the Ragnarok level-up sound) and puts them in your Calendar;
- **shows your LINE unread count** (from LINE's Dock badge; no message is read);
- **shows your Discord unread count** (DMs and @mentions, from Discord's Dock badge; no message is read);
- **reports your [Claude Code](https://claude.com/claude-code) sessions**, in the spirit of the Codex desktop pet: what each one is doing, which ones need you, and which ones have finished. Click to jump to a session.

Claude Code is optional: reminders, LINE and Discord work without it.

> เพ็ตลอยบนเดสก์ท็อป macOS: ตั้งเตือนพร้อมบันทึกลงปฏิทิน, บอกข้อความ LINE ที่ยังไม่อ่าน และรายงานงานของ Claude Code (ไม่มี Claude ก็ใช้ได้)

## Quick start

You need macOS 13 or later. No Xcode, git or Homebrew is needed.

1. Open **Terminal**: press ⌘ Space, type `Terminal`, then press Enter.
2. Paste this line and press Enter:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/mobbenxd/angeling-pet/main/get.sh | bash
   ```
3. Wait about 10 seconds for `Done!`. Angeling appears in the bottom-right corner and will start at every login.
4. Press **⌥⌘R** to set your first reminder. Click **Allow Full Access** when macOS asks about Calendar.

If you use Claude Code, it's picked up automatically. **⌥⌘A** shows or hides Angeling, and right-clicking it opens the menu.

### ติดตั้ง (ภาษาไทย)

1. เปิดแอป **Terminal**: กด ⌘ Space พิมพ์ `Terminal` แล้วกด Enter
2. วางคำสั่งข้างบน (บรรทัดที่ขึ้นต้นด้วย `curl`) แล้วกด Enter
3. รอประมาณ 10 วินาทีจนขึ้น `Done!` Angeling จะโผล่ที่มุมขวาล่าง และเปิดเองทุกครั้งที่เปิดเครื่อง
4. กด **⌥⌘R** เพื่อตั้งเตือน ถ้า macOS ถามเรื่องปฏิทิน ให้กด **Allow Full Access**

ต้องเป็น macOS 13 ขึ้นไป ขั้นตอนแบบละเอียดพร้อมวิธีแก้ปัญหาอยู่ที่ **[คู่มือการติดตั้ง](docs/Installation.md)**

## Documentation

The full guide (in Thai) is in **[docs/](docs/README.md)**.

| Getting started | Using Angeling | Maintenance and development |
|---|---|---|
| [Requirements](docs/Requirements.md) | [Usage: clicks, menus, hotkey](docs/Usage.md) | [Troubleshooting](docs/Troubleshooting.md) |
| [Installation](docs/Installation.md) | [Activity bubble and statuses](docs/Activity-Bubble.md) | [Updating and uninstalling](docs/Updating-and-Uninstalling.md) |
| [First run](docs/First-Run.md) | [Reminders](docs/Reminders.md) | [How it works](docs/How-It-Works.md) |
| | [LINE notifications](docs/LINE-Notifications.md) | [Development](docs/Development.md) |
| | [Discord notifications](docs/Discord-Notifications.md) | |
| | [Claude usage limits](docs/Usage-Limits.md) | |
| | [Emotes and animations](docs/Emotes-and-Animations.md) | |
| | [Use a different pet](docs/Custom-Pet.md) | |

## Features

- **Activity bubble**: one row per session, showing its status (กำลังทำ / ต้องดูตอนนี้ / ติดปัญหา / เสร็จแล้ว), what it is doing right now, the prompt, and the task-list progress.
- **Finished tasks**: shown in green until you open or dismiss them, or for 30 minutes.
- **Collapse and expand**: the ⌄ / ⌃ chevron on the bubble's top row switches between the two rows that matter most (with what each session is doing now; the rest counted in a "+N อื่น ๆ" line that turns orange when it hides a session waiting on you) and every session in full. Angeling remembers the choice. While collapsed, LINE and Discord counts move to badges on Angeling.
- **Claude usage limits** (off by default, menu 📊): the bubble's top row shows the weekly and 5-hour limits, e.g. `สัปดาห์ 62% · 5 ชม. 40%`, coloured blue, orange from 60% and red above 85%. Without a 5-hour window it shows the weekly reset day instead. When the bubble is hidden, a small two-layer bar under Angeling shows both; the menu can also show the bar all the time, or only the bar. Shows used or remaining. Angeling makes the `/omg` face once per cycle at 90%. Claude Code only gives these numbers to the status line, so turning this on wraps your status line (yours still runs) and turning it off puts it back. See [Claude usage limits](docs/Usage-Limits.md).
- **Click to jump**:
  - Click a row to open that session.
  - Click Angeling to open the latest active session.
  - Works for the Claude desktop app (via deep link), Terminal and iTerm2 (selects the right tab), kitty (selects the right window), [herdr](https://herdr.dev) (switches to the pane, then raises the terminal showing it), and VS Code, Cursor and Windsurf (focuses the window that holds the session, then its tab in Claude's extension; never opens a new window).
- **Hide**:
  - Hover Angeling to reveal a button that hides or shows the bubble. A red badge shows the number of active sessions while it is hidden.
  - Hide Angeling itself with ⌥⌘A or from the menu bar icon.
  - Pops back out when a session needs you (can be turned off).
- **Themes**: Classic (the pink bubble), Minimal light, Minimal dark, Liquid Glass (macOS 26+), Tokyo Night, Ragnarok (a Ragnarok Online window: blue title bar, grey frame, white list, flat rows), or follow macOS light / dark. Pick one from the ธีม menu.
- **Characters**: swap Angeling for Bee Husky (a chibi husky puppy) or one of 18 Bomber characters (Thunder, Bomber Cat, Chick Squad, Tommy Shelby and more) from the ตัวละคร menu. Each one walks, waves and blinks when hurt in place of Angeling's animations. See [Use a different pet](docs/Custom-Pet.md).
- **Ragnarok cursor**: hovering Angeling turns the pointer into the Ragnarok Online cursor, a blue and white arrowhead that spins like the one in the game. In the Ragnarok theme the bubble's rows and button use it too. The cursor is drawn by the app, so it needs no extra artwork.
- **Needs you now**: when Claude asks for permission or asks you something, the row turns red with a slow pulse and moves to the top. Angeling gets a red "!" badge and plays a short sound (can be muted).
- **Choose what the bubble shows**: right-click a row, Angeling, or the menu bar icon to turn the prompt, the latest message and the task list on or off.
- **Reminders**: press ⌥⌘R, type what to do and pick a date and time. Angeling adds a 30-minute event to your Calendar, then at that time pops out (even when hidden), plays the Ragnarok level-up sound and keeps an orange alert row until you click it or snooze it. Moving or deleting the event in Calendar moves or cancels the reminder. Adding it to Calendar needs Calendar access. See [Reminders](docs/Reminders.md).
- **Discord**: a purple Discord row shows how many DMs and @mentions are unread. The number is Discord's own Dock badge count, so no permission is needed and no message is read. Click it to open Discord. See [Discord notifications](docs/Discord-Notifications.md).
- **Update notices**: when a new release is out, a 🎁 row shows the new version. Click it to update in place. Right-click it to see what's new or skip that version.
- **LINE**: a green LINE row shows how many LINE messages are unread. The number is LINE's own Dock badge count, so no permission is needed and no message is read. Click it to open LINE. Right-click it to hide it until the count rises. See [LINE notifications](docs/LINE-Notifications.md).
- **Animations**: idle, running, reading, waiting, failed and waving, from the Codex pet sprite format. Drag Angeling and it runs along.
- **Ragnarok emotes** (`/heh` `/lv` `/wah` `/omg` `/swt` `/slur`):

  | Emote | When |
  |---|---|
  | `/heh` | A session gets a new task |
  | `/lv` | A task finishes |
  | `/wah` | A session needs your input (stays until you answer) |
  | `/omg` | A tool fails |
  | `/swt` | A session has been working for more than 5 minutes |
  | `/slur` | Nothing to do for 10 minutes |

## Requirements

| Need | For | Notes |
|---|---|---|
| macOS 13 or later | everything | Apple silicon or Intel |
| [Claude Code](https://claude.com/claude-code) | session reports (optional) | Install it before Angeling, or run the installer again afterwards |
| `jq` | session reports (optional) | Built into macOS 15+. On macOS 13–14: `brew install jq` |
| LINE / Discord for Mac | unread counts (optional) | Must be running; no permission needed |
| Xcode Command Line Tools | building from source only | `xcode-select --install` |

## Install

The installer does the following. It is safe to run again.

1. Installs `~/Applications/Angeling.app`: the prebuilt universal app from the release, or a local build when run from a git clone.
2. Copies the artwork, sounds and hook to `~/.claude/angeling-pet/`.
3. If Claude Code is installed, adds the hook to `~/.claude/settings.json`, keeping your other hooks. It saves a backup to `settings.json.angeling-backup` first.
4. Sets Angeling to start at login. Pass `--no-login` to skip this (`… | bash -s -- --no-login`).

### From source

```bash
git clone https://github.com/mobbenxd/angeling-pet.git ~/apps/angeling-pet
cd ~/apps/angeling-pet
./install.sh
```

This builds the app with `swiftc` and takes the artwork from the latest release. If you have the Codex `angeling` pet, it uses that instead; `ANGELING_CODEX_PET=<name>` picks another Codex pet. If something goes wrong, see [Troubleshooting](docs/Troubleshooting.md).

## Update

Angeling checks GitHub for a new release at launch and every 6 hours. When one is out, a 🎁 row appears in the bubble: click it and Angeling updates itself, then reopens. You can also run the Quick start command again. From a git clone, use `git pull && ./install.sh`.

## Uninstall

```bash
~/.claude/angeling-pet/uninstall.sh           # remove app, login item and hooks; restore your status line
~/.claude/angeling-pet/uninstall.sh --purge   # also delete ~/.claude/angeling-pet, reminders and preferences
```

## How it works

```
Claude Code hooks ──► hooks/angeling-hook.sh ──► ~/.claude/angeling-pet/state/<session>.json
                                                              │  (polled every 0.5 s)
                                                              ▼
                                                   Angeling.app (src/main.swift)
```

- **The hook** runs for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Notification`, `PermissionRequest`, `Stop`, `StopFailure`, `SubagentStop` and `SessionEnd`. It writes one small JSON file per session, recording:
  - the state, the current activity and the prompt;
  - the task list, read from the Claude desktop task list tool;
  - where the session lives (desktop session id, terminal app, tty, iTerm session id, kitty window id, or herdr pane id).
  
  Writes are locked per session, so parallel tool calls can't corrupt a file. It takes about 50–80 ms per event.
- **Reminders** are stored in `~/.claude/angeling-pet/reminders.json` and linked to their Calendar events through EventKit.
- **Discord** is polled every 3 s: only its Dock badge, through `lsappinfo`.
- **LINE** is polled every 3 s: only its Dock badge, through `lsappinfo`.
- **Usage limits** (when turned on): `statusLine` in `~/.claude/settings.json` runs `~/.claude/angeling-pet/statusline.sh`, which saves Claude Code's status JSON to `limits.json` and then runs your own status line. The app reads `rate_limits` from it every 3 s.
- **The app** is a single-file AppKit program. Its only network call is the update check against the GitHub releases API, which can be turned off in the menu (อัปเดต → ตรวจอัตโนมัติ). It has no dependencies and runs as an accessory app, so it has no Dock icon.

## Artwork

Ragnarok Online, Angeling, the emotes and the level-up sound are © Gravity Co., Ltd. They are **not** covered by the MIT license and are not in the git history. They are published as assets of each [GitHub Release](https://github.com/mobbenxd/angeling-pet/releases) so that installs work out of the box, and they will be removed if the rights holder asks.

`scripts/fetch-assets.sh` fills `assets/` from, in order:

- **Sprite sheet**: your Codex pet `~/.codex/pets/${ANGELING_CODEX_PET:-angeling}`, if present; otherwise the release. You can also drop any Codex v2 sheet at `assets/spritesheet.webp`. See [Use a different pet](docs/Custom-Pet.md).
- **Emotes**: the release; otherwise the [iRO Wiki emote list](https://irowiki.org/wiki/Emotes).
- **Reminder chime**: the release; otherwise [MyInstants](https://www.myinstants.com/en/instant/level-up-ragnarok/). If neither works, reminders use a macOS sound.
- **Bomber characters**: the release's `characters.zip`. The sheets come from the Bomber game; like the rest of the artwork they are not covered by the MIT license and are not in the git history. `scripts/import-characters.py <pack.zip>` rebuilds `assets/characters/` from the original pack.
- **Extra pets** (Bee Husky): the release's `pets.zip`, one Codex v2 pet per folder. `swift scripts/import-pet.swift <sheet> <id> "<Name>"` adds a pet to `assets/pets/`, fitting a generated sheet onto the exact 192×208 grid. A pet's `pet.json` can also set `animations` (`{"idle": {"frames": 16, "ms": 90}}`) for up to 16 frames per animation on a sheet up to 16 cells wide.

## Development

```bash
./scripts/build.sh                        # rebuild ~/Applications/Angeling.app
pkill -x Angeling; open ~/Applications/Angeling.app
cp hooks/angeling-hook.sh ~/.claude/angeling-pet/hook.sh   # after editing the hook
./scripts/package.sh 1.2.3                # release files into dist/
```

Snapshot testing, the debug environment variables, hook tests and the release steps are covered in the [Development](docs/Development.md) guide.

## Contributing

`main` is protected, so all changes go through pull requests. Fork the repository or create a branch, then open a PR. Documentation lives in `docs/` and changes the same way.

## License

The code is released under the [MIT](LICENSE) license. The artwork is not covered by it; see [Artwork](#artwork).
