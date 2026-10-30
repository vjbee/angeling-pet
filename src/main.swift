// Angeling — a floating desktop pet that reports Claude Code task status (Codex-pet style).
// Reads per-session JSON written by ~/.claude/angeling-pet/hook.sh.
//
// Interaction (modelled on the Codex pet overlay):
//   click pet          hop + expand/collapse the activity stack
//   click a row        jump to that session (Claude desktop / Terminal / iTerm / VS Code …)
//   right-click row    dismiss that row until the session does something new
//   drag pet           move (runs left/right while dragging)
//   right-click pet    menu: hide activity, hide Angeling, …
//   menu bar icon      always there; shows/hides Angeling, lists sessions
//   ⌥⌘A                show / hide Angeling
//   LINE row           unread count (Dock badge); click opens LINE
//   Discord row        unread DMs + @mentions (Dock badge count); click opens Discord
//   ⌥⌘R                set a reminder (also added to Calendar); Angeling chimes at the time
//   update row         a newer GitHub release exists; click to install it
import AppKit
import Carbon.HIToolbox
import EventKit

let home = FileManager.default.homeDirectoryForCurrentUser
let baseDir = home.appendingPathComponent(".claude/angeling-pet")
// Debug: ANGELING_STATE_DIR points snapshots at fake session files instead of the real ones.
let stateDir = ProcessInfo.processInfo.environment["ANGELING_STATE_DIR"].map { URL(fileURLWithPath: $0) }
    ?? baseDir.appendingPathComponent("state")

// MARK: - Sprite sheet (Codex pet format v2: 8 cols x 11 rows, 192x208 cells)

struct Anim {
    let row: Int
    let durations: [Double] // ms per frame
    let loops: Bool
}

func strip(_ row: Int, _ count: Int, _ dur: Double, _ last: Double, loops: Bool = true) -> Anim {
    Anim(row: row, durations: Array(repeating: dur, count: count - 1) + [last], loops: loops)
}

/// A character's artwork: frames on rows of 192x208 cells, plus which row and timing each animation uses.
protocol Sprite: AnyObject {
    var anims: [String: Anim] { get }
    func frame(row: Int, col: Int) -> NSImage?
}

let cellSize = NSSize(width: 192, height: 208)

let codexAnims: [String: Anim] = [
    "idle": Anim(row: 0, durations: [1400, 110, 110, 140, 140, 320, 900], loops: true),
    "running-right": strip(1, 8, 120, 220),
    "running-left": strip(2, 8, 120, 220),
    "waving": strip(3, 4, 140, 280),
    "jumping": strip(4, 5, 140, 280, loops: false),
    "failed": strip(5, 8, 140, 240),
    "waiting": strip(6, 6, 150, 260),
    "running": strip(7, 6, 120, 220),
    "review": strip(8, 6, 150, 280),
]

final class SpriteSheet: Sprite {
    private var cache: [String: NSImage] = [:]
    let image: CGImage
    var anims: [String: Anim] { codexAnims }

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        image = cg
    }

    func frame(row: Int, col: Int) -> NSImage? {
        let key = "\(row)-\(col)"
        if let c = cache[key] { return c }
        let rect = CGRect(x: CGFloat(col) * cellSize.width, y: CGFloat(row) * cellSize.height, width: cellSize.width, height: cellSize.height)
        guard let cg = image.cropping(to: rect) else { return nil }
        let img = NSImage(cgImage: cg, size: cellSize)
        cache[key] = img
        return img
    }
}

/// Extra Codex v2 pets in ~/.claude/angeling-pet/pets/<id>/ (pet.json + sheet), made by scripts/import-pet.swift.
struct CodexPet: Decodable {
    let id: String
    let displayName: String
    let spritesheetPath: String?
    var sheetURL: URL { petsDir.appendingPathComponent(id).appendingPathComponent(spritesheetPath ?? "spritesheet.webp") }
}

let petsDir = baseDir.appendingPathComponent("pets")
let codexPets: [CodexPet] = {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: petsDir, includingPropertiesForKeys: nil) else { return [] }
    return dirs.compactMap { dir -> CodexPet? in
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("pet.json")),
              let p = try? JSONDecoder().decode(CodexPet.self, from: data),
              p.id == dir.lastPathComponent, p.id != "angeling", fm.fileExists(atPath: p.sheetURL.path) else { return nil }
        return p
    }.sorted { $0.displayName < $1.displayName }
}()

// MARK: - Bomber characters (assets/characters, made by scripts/import-characters.py)

/// One frame: a rect on one of the character's sheets. Stored as [file, x, y, w, h].
struct BomberFrame: Decodable {
    let file: String
    let rect: CGRect
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        file = try c.decode(String.self)
        rect = CGRect(x: try c.decode(Double.self), y: try c.decode(Double.self),
                      width: try c.decode(Double.self), height: try c.decode(Double.self))
    }
}

/// Rows: walk down, walk left, walk right, walk up, place, hurt; 4 frames each.
struct BomberCharacter: Decodable {
    let id: String
    let name: String
    let rows: [[BomberFrame]]
    let flip: [Int]   // rows drawn mirrored
}

let charactersDir = baseDir.appendingPathComponent("characters")
let bomberCharacters: [BomberCharacter] = {
    guard let data = try? Data(contentsOf: charactersDir.appendingPathComponent("characters.json")),
          let all = try? JSONDecoder().decode([BomberCharacter].self, from: data) else { return [] }
    let fm = FileManager.default
    return all.filter { c in c.rows.count == 6 && c.rows.allSatisfy { $0.count == 4 }
        && c.rows.joined().allSatisfy { fm.fileExists(atPath: charactersDir.appendingPathComponent($0.file).path) } }
}()

let bomberAnims: [String: Anim] = [
    "idle": Anim(row: 0, durations: [1600, 180, 180, 180], loops: true),
    "running-right": strip(2, 4, 130, 130),
    "running-left": strip(1, 4, 130, 130),
    "waving": strip(4, 4, 150, 220),
    "jumping": strip(4, 4, 130, 200, loops: false),
    "failed": strip(5, 4, 140, 220),
    "waiting": strip(4, 4, 180, 400),
    "running": strip(0, 4, 140, 140),
    "review": strip(0, 4, 220, 220),
]

/// Draws a Bomber character's frames into Angeling-sized cells, so the rest of the app treats it
/// like a Codex sheet. Sheets differ in resolution, so each sheet gets one scale that fits its
/// largest frame; the figure stands on the cell's bottom edge.
final class BomberSprite: Sprite {
    let character: BomberCharacter
    private var sheets: [String: CGImage] = [:]
    private var scales: [String: CGFloat] = [:]
    private var cache: [String: NSImage] = [:]
    var anims: [String: Anim] { bomberAnims }

    init?(_ character: BomberCharacter) {
        self.character = character
        let box = NSSize(width: 184, height: 196)
        for f in character.rows.joined() where sheets[f.file] == nil {
            guard let img = NSImage(contentsOf: charactersDir.appendingPathComponent(f.file)),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            sheets[f.file] = cg
            let same = character.rows.joined().filter { $0.file == f.file }
            scales[f.file] = min(box.width / same.map(\.rect.width).max()!, box.height / same.map(\.rect.height).max()!)
        }
    }

    func frame(row: Int, col: Int) -> NSImage? {
        let key = "\(row)-\(col)"
        if let c = cache[key] { return c }
        guard character.rows.indices.contains(row), character.rows[row].indices.contains(col) else { return nil }
        let f = character.rows[row][col]
        guard let cg = sheets[f.file]?.cropping(to: f.rect), let scale = scales[f.file] else { return nil }
        let size = NSSize(width: f.rect.width * scale, height: f.rect.height * scale)
        let img = NSImage(size: cellSize)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        if character.flip.contains(row) {
            let t = NSAffineTransform()
            t.translateX(by: cellSize.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
        }
        // Hurt frames blink, as in the game.
        NSImage(cgImage: cg, size: size).draw(in: NSRect(x: (cellSize.width - size.width) / 2, y: 4, width: size.width, height: size.height),
                                              from: .zero, operation: .sourceOver, fraction: row == 5 && col % 2 == 1 ? 0.35 : 1)
        img.unlockFocus()
        cache[key] = img
        return img
    }
}

// MARK: - Session state

struct PlanItem: Decodable { let c: String; let s: String }

struct SessionState: Decodable {
    let session: String?
    let cwd: String?
    let project: String?
    let task: String?
    let state: String?
    let text: String?
    let updated: Double?
    let plan: [PlanItem]?
    // Where the session lives, for click-to-open.
    let host: String?   // Claude desktop session id (local_…)
    let app: String?    // bundle id of the hosting app
    let term: String?
    let tty: String?
    let iterm: String?
    let herdr: String?      // herdr pane id (w4S:p1) when the session runs inside herdr
    let herdrBin: String?
    let herdrSock: String?
    let kittyWin: String?    // KITTY_WINDOW_ID when the session runs straight in kitty
    let kittyListen: String? // KITTY_LISTEN_ON (set only when kitty.conf has listen_on)
    let root: String?        // CLAUDE_PROJECT_DIR: where the session started, unlike cwd it never moves
}

func loadSessions() -> [SessionState] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: stateDir, includingPropertiesForKeys: nil) else { return [] }
    let now = Date().timeIntervalSince1970
    var out: [SessionState] = []
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let s = try? JSONDecoder().decode(SessionState.self, from: data) else { continue }
        // Forget sessions that went silent for 6 hours (crashed / closed without SessionEnd).
        if now - (s.updated ?? 0) > 6 * 3600 { try? fm.removeItem(at: f); continue }
        out.append(s)
    }
    return out
}

/// What a session means right now, after aging out transient states.
func effective(_ s: SessionState, now: Double) -> String {
    let age = now - (s.updated ?? 0)
    switch s.state ?? "idle" {
    case "running", "review": return age > 600 ? "idle" : s.state!
    case "failed": return age > 20 ? "running" : "failed"
    case "done": return age > 1800 ? "idle" : "done"
    case "waiting": return "waiting"
    default: return "idle"
    }
}

func priority(_ st: String) -> Int {
    switch st {
    case "waiting": return 5
    case "failed": return 4
    case "running", "review": return 3
    case "done": return 2
    default: return 1
    }
}

let alarmOrange = NSColor(calibratedRed: 0.93, green: 0.48, blue: 0.08, alpha: 1)
let alertRed = NSColor(calibratedRed: 0.86, green: 0.15, blue: 0.2, alpha: 1)
let discordBlurple = NSColor(calibratedRed: 0.35, green: 0.4, blue: 0.95, alpha: 1)
let lineGreen = NSColor(calibratedRed: 0.02, green: 0.66, blue: 0.3, alpha: 1)

// MARK: - Themes
//   Classic is the original pink bubble. The minimal themes drop emoji and framed rows: a coloured
//   dot marks each row's state, the status sits on the right, and only rows that need you are tinted.
//   Ragnarok draws the bubble as a Ragnarok Online window: blue title bar, grey body, white list box,
//   flat rows with a light-blue highlight and a coloured bar on rows that need you.

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

struct Theme {
    let id: String
    let minimal: Bool
    let bubbleFill: NSColor, bubbleStroke: NSColor
    let text: NSColor, secondary: NSColor, project: NSColor, hover: NSColor
    let running: NSColor, done: NSColor, alert: NSColor, alarm: NSColor, gold: NSColor, line: NSColor, discord: NSColor
    var glassTint: NSColor? = nil   // set = the bubble is real Liquid Glass in this tint

    static let classic = Theme(
        id: "classic", minimal: false,
        bubbleFill: NSColor(calibratedRed: 1, green: 0.98, blue: 0.97, alpha: 0.97),
        bubbleStroke: NSColor(calibratedRed: 0.86, green: 0.55, blue: 0.6, alpha: 1),
        text: NSColor(calibratedWhite: 0.15, alpha: 1), secondary: NSColor(calibratedWhite: 0.45, alpha: 1),
        project: NSColor(calibratedRed: 0.72, green: 0.3, blue: 0.4, alpha: 1),
        hover: NSColor(calibratedRed: 1, green: 0.85, blue: 0.88, alpha: 0.7),
        running: NSColor(calibratedWhite: 0.45, alpha: 1), done: NSColor(calibratedRed: 0.2, green: 0.62, blue: 0.33, alpha: 1),
        alert: alertRed, alarm: alarmOrange, gold: NSColor(calibratedRed: 0.8, green: 0.55, blue: 0.05, alpha: 1),
        line: lineGreen, discord: discordBlurple)
    static let light = Theme(
        id: "light", minimal: true, bubbleFill: hex(0xffffff, 0.97), bubbleStroke: hex(0x000000, 0.1),
        text: hex(0x1d1d1f), secondary: hex(0x6e6e73), project: hex(0x1d1d1f), hover: hex(0x000000, 0.05),
        running: hex(0x0a72e0), done: hex(0x1f8a4c), alert: hex(0xd93036), alarm: hex(0xc8650a), gold: hex(0xa66a10),
        line: hex(0x06a84d), discord: hex(0x5865f2))
    static let dark = Theme(
        id: "dark", minimal: true, bubbleFill: hex(0x1c1c1e, 0.96), bubbleStroke: hex(0xffffff, 0.12),
        text: hex(0xf5f5f7), secondary: hex(0xa1a1a6), project: hex(0xf5f5f7), hover: hex(0xffffff, 0.07),
        running: hex(0x3b9eff), done: hex(0x3dd68c), alert: hex(0xff6369), alarm: hex(0xffa94d), gold: hex(0xf5c451),
        line: hex(0x3ddc84), discord: hex(0x8b93ff))
    static let tokyoNight = Theme(
        id: "tokyo", minimal: true, bubbleFill: hex(0x1a1b26, 0.97), bubbleStroke: hex(0x292e42),
        text: hex(0xc0caf5), secondary: hex(0xa9b1d6), project: hex(0xc0caf5), hover: hex(0x292e42),
        running: hex(0x7aa2f7), done: hex(0x9ece6a), alert: hex(0xf7768e), alarm: hex(0xff9e64), gold: hex(0xe0af68),
        line: hex(0x73daca), discord: hex(0xbb9af7))
    /// System colours, so the text follows macOS light / dark. bubbleFill is the pre-macOS 26 fallback
    /// and the hide button's fill; the tint is a faint Angeling pink.
    static let glass = Theme(
        id: "glass", minimal: true, bubbleFill: NSColor.windowBackgroundColor.withAlphaComponent(0.72), bubbleStroke: .separatorColor,
        text: .labelColor, secondary: .secondaryLabelColor, project: .labelColor, hover: hex(0xffffff, 0.14),
        running: .systemBlue, done: .systemGreen, alert: .systemRed, alarm: .systemOrange, gold: .systemYellow,
        line: .systemGreen, discord: .systemIndigo, glassTint: hex(0xff8fb8, 0.16))

    static let ragnarok = Theme(
        id: "ragnarok", minimal: false, bubbleFill: hex(0xf6f6f6), bubbleStroke: hex(0x7d8494),
        text: hex(0x000000), secondary: hex(0x5a5a5a), project: hex(0x000000), hover: hex(0xc9d9fb),
        running: hex(0x5f6066), done: hex(0x2c8a3a), alert: hex(0xd1262e), alarm: hex(0xd8730c), gold: hex(0xb07c08),
        line: hex(0x06a84d), discord: hex(0x5865f2))

    var ragnarok: Bool { id == "ragnarok" }

    /// Menu choices in order: (setting value, menu title). "auto" follows macOS light / dark.
    static let choices = [("auto", "ตามระบบ (Minimal สว่าง / มืด)"), ("light", "Minimal สว่าง"), ("dark", "Minimal มืด"),
                          ("glass", "Liquid Glass"), ("tokyo", "Tokyo Night"), ("ragnarok", "Ragnarok"), ("classic", "Classic (ชมพู)")]

    static func named(_ id: String) -> Theme {
        switch id {
        case "light": return light
        case "dark": return dark
        case "tokyo": return tokyoNight
        case "ragnarok": return ragnarok
        case "glass": return glass
        case "auto":
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        default: return classic
        }
    }

    /// Colour of a session state: the dot in minimal themes.
    func color(_ state: String) -> NSColor {
        switch state {
        case "waiting": return alert
        case "failed": return alarm
        case "done": return done
        case "running", "review": return running
        default: return secondary
        }
    }
}

var theme = Theme.classic
let clockTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
let icons: [String: String] = ["waiting": "⚠️", "failed": "😣", "running": "⚙️", "review": "🔍", "done": "✨", "idle": "💤"]
let statusLabel: [String: String] = ["waiting": "ต้องดูตอนนี้", "failed": "ติดปัญหา", "running": "กำลังทำ",
                                     "review": "กำลังอ่าน", "done": "เสร็จแล้ว", "idle": "ว่าง"]

// MARK: - Jump to a session's window

enum Focus {
    static func open(_ s: SessionState) {
        let app = s.app ?? ""
        if let host = s.host, host.hasPrefix("local_") {
            openURL("claude://code/continue?session=\(host)&source=desktop_action")
        } else if let pane = s.herdr {
            // herdr runs the session in a headless server: switch herdr to the pane, then raise
            // the terminal window (kitty, Ghostty, …) that shows a herdr client.
            DispatchQueue.global().async {
                var env = ProcessInfo.processInfo.environment
                if let sock = s.herdrSock { env["HERDR_SOCKET_PATH"] = sock }
                output(s.herdrBin ?? NSHomeDirectory() + "/.local/bin/herdr", ["agent", "focus", pane], env: env)
                guard let c = herdrClient() else { return }
                // ps -E appends the client's environment, where kitty names the window it runs in.
                let vars = (output("/bin/ps", ["-E", "-o", "command=", "-p", "\(c.pid)"]) ?? "").split(separator: " ")
                func v(_ k: String) -> String? { vars.first { $0.hasPrefix(k + "=") }.map { String($0.dropFirst(k.count + 1)) } }
                if c.app.bundleIdentifier == kittyBundle, let win = v("KITTY_WINDOW_ID"), let listen = v("KITTY_LISTEN_ON") {
                    kittyFocus(c.app.bundleURL, window: win, listen: listen)
                }
                DispatchQueue.main.async { c.app.activate(options: []) }
            }
        } else if app == kittyBundle, let win = s.kittyWin, let listen = s.kittyListen {
            DispatchQueue.global().async {
                kittyFocus(NSWorkspace.shared.urlForApplication(withBundleIdentifier: kittyBundle), window: win, listen: listen)
                DispatchQueue.main.async {
                    NSRunningApplication.runningApplications(withBundleIdentifier: kittyBundle).first?.activate(options: [])
                }
            }
        } else if app == "com.apple.Terminal" || s.term == "Apple_Terminal", let tty = s.tty {
            osa("""
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                  end if
                end repeat
              end repeat
              activate
            end tell
            """)
        } else if app == "com.googlecode.iterm2" || s.term == "iTerm.app", let it = s.iterm,
                  let uuid = it.split(separator: ":").last {
            osa("""
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with ss in sessions of t
                    if unique id of ss is "\(uuid)" then
                      select w
                      select t
                      select ss
                    end if
                  end repeat
                end repeat
              end repeat
              activate
            end tell
            """)
        } else if ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"].contains(app)
                    || s.term == "vscode", let cwd = s.cwd {
            let bid = app.isEmpty ? "com.microsoft.VSCode" : app
            // The project root, not cwd: a session can move into a folder that another window holds.
            if let folder = ideWindowFolder(bundle: bid, path: s.root ?? cwd) {
                // Re-opening a window's own folder focuses it; any other folder would open a new window.
                run("/usr/bin/open", ["-b", bid, folder])
                // Claude's extension reveals the session's tab, or resumes a copy if the URI lands in
                // another window, so it has to follow the focus. Sessions in the IDE's terminal have
                // a TERM_PROGRAM and no tab.
                if s.term == nil, let id = s.session, let scheme = ideSchemes[bid] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        openURL("\(scheme)://anthropic.claude-code/open?session=\(id)")
                    }
                }
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } else if !app.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static let kittyBundle = "net.kovidgoyal.kitty"
    static let ideSchemes = ["com.microsoft.VSCode": "vscode", "com.todesktop.230313mzl4w4u92": "cursor", "com.exafunction.windsurf": "windsurf"]

    /// Root folder of the open IDE window holding `path`, from the lock file Claude's extension keeps
    /// per window in ~/.claude/ide. A dead pid drops stale locks. Multi-root windows are skipped:
    /// opening one of their folders would start a new window.
    static func ideWindowFolder(bundle: String, path: String) -> String? {
        struct Lock: Decodable { let pid: Int32; let workspaceFolders: [String] }
        let files = (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(".claude/ide"), includingPropertiesForKeys: nil)) ?? []
        let target = path.lowercased() + "/"
        var best: String?
        for f in files where f.pathExtension == "lock" {
            guard let data = try? Data(contentsOf: f), let lock = try? JSONDecoder().decode(Lock.self, from: data),
                  lock.workspaceFolders.count == 1, let folder = lock.workspaceFolders.first,
                  NSRunningApplication(processIdentifier: lock.pid)?.bundleIdentifier == bundle,
                  target.hasPrefix(folder.lowercased() + "/"), folder.count > (best?.count ?? 0) else { continue }
            best = folder
        }
        return best
    }

    /// A local herdr client and the GUI app it runs in: walk up from each `herdr` process until an
    /// ancestor is a regular app. Skips the server and `herdr --remote` (another machine's herdr).
    static func herdrClient() -> (pid: Int32, app: NSRunningApplication)? {
        var parent: [Int32: Int32] = [:]
        var clients: [Int32] = []
        for line in (output("/bin/ps", ["-axo", "pid=,ppid=,command="]) ?? "").split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            parent[pid] = ppid
            let cmd = f[2].split(separator: " ")
            if cmd.first.map({ $0.hasSuffix("/herdr") || $0 == "herdr" }) == true,
               !cmd.contains(where: { ["server", "client", "--remote"].contains($0) }) {
                clients.append(pid)
            }
        }
        for c in clients {
            var pid = c
            while let pp = parent[pid], pp > 1 {
                if let a = NSRunningApplication(processIdentifier: pp), a.activationPolicy == .regular { return (c, a) }
                pid = pp
            }
        }
        return nil
    }

    /// Focus one kitty window over kitty's remote-control socket. Needs `allow_remote_control` and
    /// `listen_on` in kitty.conf; without them kitty only comes to the front.
    static func kittyFocus(_ app: URL?, window: String, listen: String) {
        guard let app else { return }
        output(app.appendingPathComponent("Contents/MacOS/kitten").path,
               ["@", "--to", listen, "focus-window", "--match", "id:\(window)"])
    }

    /// Run a tool and wait for it; its stdout, or nil when it could not start.
    @discardableResult
    static func output(_ path: String, _ args: [String], env: [String: String]? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env { p.environment = env }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func openURL(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    static func osa(_ script: String) {
        DispatchQueue.global().async { run("/usr/bin/osascript", ["-e", script]) }
    }

    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}

// MARK: - LINE
//   Unread count = LINE's Dock badge (lsappinfo; no permission needed, LINE must be running).
//   No message is ever read.

enum LineWatch {
    static let bundle = "jp.naver.line.mac"

    static func unread() -> Int {
        if let fake = ProcessInfo.processInfo.environment["ANGELING_LINE_UNREAD"] { return Int(fake) ?? 0 }
        return dockBadge(bundle).flatMap { Int($0.filter(\.isNumber)) } ?? 0
    }

    static func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Discord
//   Unread count = Discord's Dock badge (lsappinfo; no permission needed, Discord must be running).
//   The number counts direct messages and @mentions; a plain "•" (unread server chatter) is ignored.
//   No message is ever read.

enum DiscordWatch {
    static let bundle = "com.hnc.Discord"

    static func unread() -> Int {
        if let fake = ProcessInfo.processInfo.environment["ANGELING_DISCORD_UNREAD"] { return Int(fake) ?? 0 }
        return dockBadge(bundle).flatMap { Int($0.filter(\.isNumber)) } ?? 0
    }

    static func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Dock badge text of a running app ("" when it has none), e.g. `"StatusLabel"={ "label"="676" }`;
/// nil when the app is not running.
func dockBadge(_ bundle: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
    p.arguments = ["info", "-only", "StatusLabel", "-app", bundle]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard !text.isEmpty else { return nil }
    guard let r = text.range(of: #""label"="[^"]*""#, options: .regularExpression) else { return "" }
    return String(text[r].dropFirst(9).dropLast())
}

// MARK: - Updates
//   Checks the latest GitHub release at launch and every 6 hours (the only network call Angeling
//   makes; it can be turned off). Updating runs the one-line installer in the background: it
//   replaces the app, quits this copy and opens the new one.

enum Updater {
    static let repo = "mobbenxd/angeling-pet"
    static var current: String {
        ProcessInfo.processInfo.environment["ANGELING_FAKE_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    static let log = baseDir.appendingPathComponent("update.log")

    /// "1.10.0" > "1.9.2"; false for anything that isn't a dotted number (e.g. "dev").
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let p = v.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) }
            return p.isEmpty || p.contains(nil) ? nil : p.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l > r }
        }
        return false
    }

    /// Latest release version (without the "v") and its page; nil on any failure.
    static func fetchLatest(_ done: @escaping (String?, URL?) -> Void) {
        if let fake = ProcessInfo.processInfo.environment["ANGELING_LATEST_VERSION"] {
            return done(fake, URL(string: "https://github.com/\(repo)/releases"))
        }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 15)
        req.setValue("Angeling/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String).map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async { done(tag, page) }
        }.resume()
    }

    /// Runs the one-line installer detached, keeping the login item only if it is set up now.
    static func install() {
        let loginItem = FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/LaunchAgents/local.angeling.pet.plist").path)
        let cmd = ProcessInfo.processInfo.environment["ANGELING_UPDATE_CMD"]
            ?? "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/get.sh | bash -s --\(loginItem ? "" : " --no-login")"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "(\(cmd)) > '\(log.path)' 2>&1"]
        try? p.run()
    }
}

// MARK: - Reminders
//   Set from the reminder form (⌥⌘R). Each one is also a 30-min event in Calendar (EventKit);
//   moving or deleting that event in Calendar moves or drops the reminder. At the time,
//   Angeling pops out, chimes, and keeps an alert row until you click it or snooze it.

struct Reminder: Codable, Equatable {
    var id = UUID().uuidString
    var title: String
    var date: Double             // event start (unix)
    var eventId: String?         // the Calendar event, when one was added
    var snoozedUntil: Double?
    var firedAt: Double?         // when it started ringing
    var alertAt: Double { snoozedUntil ?? date }
}

let reminderTime: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "th_TH"); f.dateFormat = "d MMM HH:mm"; return f }()
func reminderWhen(_ t: Double) -> String {
    let d = Date(timeIntervalSince1970: t)
    return Calendar.current.isDateInToday(d) ? clockTime.string(from: d) : reminderTime.string(from: d)
}

final class ReminderStore {
    let ek = EKEventStore()
    private(set) var items: [Reminder] = []
    let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ANGELING_REMINDERS"]
                  ?? baseDir.appendingPathComponent("reminders.json").path)

    init() {
        items = (try? JSONDecoder().decode([Reminder].self, from: Data(contentsOf: url))) ?? []
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            self?.syncWithCalendar()
        }
    }

    private func save() {
        items.sort { $0.alertAt < $1.alertAt }
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    var calendarAccess: Bool {
        // .fullAccess (macOS 14+) and the older .authorized share raw value 3.
        EKEventStore.authorizationStatus(for: .event).rawValue == 3
    }
    var accessUndetermined: Bool { EKEventStore.authorizationStatus(for: .event) == .notDetermined }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(macOS 14, *) { ek.requestFullAccessToEvents(completion: finish) }
        else { ek.requestAccess(to: .event, completion: finish) }
    }

    var writableCalendars: [EKCalendar] {
        calendarAccess ? ek.calendars(for: .event).filter(\.allowsContentModifications) : []
    }

    /// Saves the reminder, adding a Calendar event when `calendar` is given. Returns an error message on failure.
    func add(title: String, date: Date, calendar: EKCalendar?) -> String? {
        var r = Reminder(title: title, date: date.timeIntervalSince1970)
        if let cal = calendar {
            let ev = EKEvent(eventStore: ek)
            ev.title = title
            ev.startDate = date
            ev.endDate = date.addingTimeInterval(1800)
            ev.calendar = cal
            ev.notes = "ตั้งเตือนจาก Angeling"
            do { try ek.save(ev, span: .thisEvent); r.eventId = ev.eventIdentifier }
            catch { return "เพิ่มลงปฏิทินไม่สำเร็จ: \(error.localizedDescription)" }
        }
        items.append(r)
        save()
        return nil
    }

    func remove(_ id: String, deleteEvent: Bool = false) {
        guard let r = items.first(where: { $0.id == id }) else { return }
        if deleteEvent, let eid = r.eventId, let ev = ek.event(withIdentifier: eid) { try? ek.remove(ev, span: .thisEvent) }
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ id: String, _ change: (inout Reminder) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    /// Follow edits made in Calendar: a moved event moves the reminder, a deleted one drops it.
    func syncWithCalendar() {
        guard calendarAccess else { return }
        var changed = false
        items = items.compactMap { r in
            guard let eid = r.eventId, r.firedAt == nil else { return r }
            guard let ev = ek.event(withIdentifier: eid) else { changed = true; return nil }
            var n = r
            n.title = ev.title ?? r.title
            n.date = ev.startDate.timeIntervalSince1970
            if n != r { changed = true }
            return n
        }
        if changed { save() }
    }
}

/// Small window: what, when, which calendar.
final class ReminderForm: NSObject {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 262),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let titleField = NSTextField()
    let picker = NSDatePicker()
    let addToCalendar = NSButton(checkboxWithTitle: "เพิ่มลงปฏิทิน", target: nil, action: nil)
    let calendarPopup = NSPopUpButton()
    let note = NSTextField(labelWithString: "")
    let store: ReminderStore
    var onSaved: (() -> Void)?
    var calendars: [EKCalendar] = []

    init(store: ReminderStore) {
        self.store = store
        super.init()
        window.title = "ตั้งเตือนกับ Angeling"
        window.isReleasedWhenClosed = false
        window.level = .floating
        let v = window.contentView!
        func label(_ t: String, y: CGFloat) {
            let l = NSTextField(labelWithString: t)
            l.font = .boldSystemFont(ofSize: 12)
            l.frame = NSRect(x: 20, y: y, width: 340, height: 17)
            v.addSubview(l)
        }
        label("จะทำอะไร", y: 230)
        titleField.placeholderString = "เช่น ประชุมทีม, โทรหาแม่"
        titleField.frame = NSRect(x: 20, y: 202, width: 340, height: 24)
        v.addSubview(titleField)

        label("เมื่อไร", y: 174)
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.frame = NSRect(x: 20, y: 146, width: 200, height: 24)
        v.addSubview(picker)
        var x: CGFloat = 20
        for (t, sel) in [("+15 นาที", #selector(plus15)), ("+1 ชม.", #selector(plus60)), ("พรุ่งนี้ 9:00", #selector(tomorrow9))] {
            let b = NSButton(title: t, target: self, action: sel)
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.sizeToFit()
            b.frame.origin = NSPoint(x: x, y: 116)
            v.addSubview(b)
            x += b.frame.width + 6
        }

        addToCalendar.frame = NSRect(x: 20, y: 80, width: 120, height: 20)
        addToCalendar.target = self
        addToCalendar.action = #selector(calendarToggled)
        v.addSubview(addToCalendar)
        calendarPopup.frame = NSRect(x: 140, y: 76, width: 220, height: 26)
        v.addSubview(calendarPopup)

        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        note.frame = NSRect(x: 20, y: 44, width: 340, height: 28)
        v.addSubview(note)

        let cancel = NSButton(title: "ยกเลิก", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 176, y: 10, width: 90, height: 30)
        v.addSubview(cancel)
        let ok = NSButton(title: "ตั้งเตือน", target: self, action: #selector(save))
        ok.keyEquivalent = "\r"
        ok.frame = NSRect(x: 270, y: 10, width: 90, height: 30)
        v.addSubview(ok)
    }

    func show() {
        titleField.stringValue = ""
        note.stringValue = ""
        // Next half hour.
        let now = Date().timeIntervalSince1970
        picker.dateValue = Date(timeIntervalSince1970: (floor(now / 1800) + 1) * 1800)
        addToCalendar.state = UserDefaults.standard.object(forKey: "reminderAddToCalendar") as? Bool ?? true ? .on : .off
        reloadCalendars()
        if store.accessUndetermined && ProcessInfo.processInfo.environment["ANGELING_SNAPSHOT"] == nil { store.requestAccess { [weak self] _ in self?.reloadCalendars() } }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(titleField)
    }

    func reloadCalendars() {
        calendars = store.writableCalendars
        calendarPopup.removeAllItems()
        for c in calendars { calendarPopup.addItem(withTitle: c.title) }
        let saved = UserDefaults.standard.string(forKey: "reminderCalendar")
        let def = store.calendarAccess ? store.ek.defaultCalendarForNewEvents?.calendarIdentifier : nil
        if let i = calendars.firstIndex(where: { $0.calendarIdentifier == saved }) ?? calendars.firstIndex(where: { $0.calendarIdentifier == def }) {
            calendarPopup.selectItem(at: i)
        }
        addToCalendar.isEnabled = !calendars.isEmpty
        calendarToggled()
        if !store.calendarAccess && !store.accessUndetermined {
            note.stringValue = "Angeling ยังไม่ได้รับสิทธิ์เข้าถึงปฏิทิน จะเตือนใน Angeling อย่างเดียว (ให้สิทธิ์ได้ที่เมนู → ให้สิทธิ์ปฏิทิน…)"
        }
    }

    @objc func calendarToggled() { calendarPopup.isEnabled = addToCalendar.isEnabled && addToCalendar.state == .on }
    @objc func plus15() { picker.dateValue = picker.dateValue.addingTimeInterval(900) }
    @objc func plus60() { picker.dateValue = picker.dateValue.addingTimeInterval(3600) }
    @objc func tomorrow9() {
        let cal = Calendar.current
        let t = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        picker.dateValue = cal.date(bySettingHour: 9, minute: 0, second: 0, of: t)!
    }
    @objc func cancel() { window.close() }

    @objc func save() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { note.stringValue = "ใส่ก่อนว่าจะทำอะไรนะ~"; NSSound.beep(); return }
        guard picker.dateValue.timeIntervalSinceNow > -60 else { note.stringValue = "เวลานี้ผ่านไปแล้ว เลือกเวลาใหม่นะ"; NSSound.beep(); return }
        let useCalendar = addToCalendar.isEnabled && addToCalendar.state == .on
        let cal = useCalendar && calendarPopup.indexOfSelectedItem >= 0 ? calendars[calendarPopup.indexOfSelectedItem] : nil
        if let err = store.add(title: title, date: picker.dateValue, calendar: cal) { note.stringValue = err; NSSound.beep(); return }
        UserDefaults.standard.set(addToCalendar.state == .on, forKey: "reminderAddToCalendar")
        if let c = cal { UserDefaults.standard.set(c.calendarIdentifier, forKey: "reminderCalendar") }
        window.close()
        onSaved?()
    }
}

// MARK: - Activity rows + bubble

/// Pointer for clickable things: the Ragnarok cursor in the Ragnarok theme, a pointing hand otherwise.
/// Returns whether it took the Ragnarok cursor, so the exit releases the same one even if the theme changed.
func pointerEntered() -> Bool {
    if theme.ragnarok { ROCursor.enter(); return true }
    NSCursor.pointingHand.set()
    return false
}
func pointerExited(_ ro: Bool) { if ro { ROCursor.exit() } else { NSCursor.arrow.set() } }

final class RowView: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    var accent: NSColor? { didSet { needsDisplay = true } }
    /// Slowly pulse the accent border (rows that need you now).
    var pulse = false { didSet { syncPulse() } }
    private var pulseTimer: Timer?

    private func syncPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        guard pulse, window != nil else { return }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.needsDisplay = true }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); syncPulse() }

    init(text: NSAttributedString, width: CGFloat, clickable: Bool) {
        super.init(frame: .zero)
        label.attributedStringValue = text
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.preferredMaxLayoutWidth = width - 16
        let h = ceil(label.fittingSize.height)
        frame = NSRect(x: 0, y: 0, width: width, height: h + 10)
        label.frame = NSRect(x: 8, y: 5, width: width - 16, height: h)
        addSubview(label)
        if clickable {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) && (onClick != nil || onRightClick != nil) ? self : super.hitTest(point)
    }
    override func draw(_ dirtyRect: NSRect) {
        if let a = accent {
            // 0…1 on a 1.6 s cycle while pulsing; steady otherwise.
            let p = pulse ? (1 - cos(Date().timeIntervalSinceReferenceDate * 2 * .pi / 1.6)) / 2 : 1
            if theme.ragnarok {
                // Flat tint with a bar on the left, like a selected line in a Ragnarok list.
                (hovering ? theme.hover : a.withAlphaComponent(0.12 + (pulse ? 0.1 * p : 0))).setFill()
                bounds.fill()
                a.withAlphaComponent(pulse ? 0.45 + 0.55 * p : 1).setFill()
                NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
                return
            }
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 1.25), xRadius: theme.minimal ? 10 : 8, yRadius: theme.minimal ? 10 : 8)
            if theme.minimal {
                // A tint only, no frame.
                a.withAlphaComponent((hovering ? 0.2 : 0.13) + (pulse ? 0.1 * p : 0)).setFill()
                path.fill()
                return
            }
            a.withAlphaComponent((hovering ? 0.22 : 0.1) + (pulse ? 0.08 * p : 0)).setFill()
            path.fill()
            a.withAlphaComponent(pulse ? 0.35 + 0.65 * p : 1).setStroke()
            path.lineWidth = pulse ? 1.5 + p : 1.5
            path.stroke()
            return
        }
        guard hovering else { return }
        theme.hover.setFill()
        if theme.ragnarok { bounds.fill(); return }
        NSBezierPath(roundedRect: bounds, xRadius: theme.minimal ? 10 : 8, yRadius: theme.minimal ? 10 : 8).fill()
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; roCursor = pointerEntered() }
    override func mouseExited(with e: NSEvent) { hovering = false; pointerExited(roCursor) }
    private var roCursor = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }
    override func rightMouseDown(with e: NSEvent) { onRightClick?(e) }
}

// Swift 6.2 ships with the macOS 26 SDK; source builds on older tools keep the plain fallback.
#if compiler(>=6.2)
@available(macOS 26, *)
final class GlassBackground: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks belong to the bubble
}
#endif

final class BubbleView: NSView {
    var onClick: (() -> Void)?
    /// Liquid Glass behind the rows (macOS 26+). The system shapes it, so it has no tail.
    private var glass: NSView?
    private var glassFrame: NSRect { NSRect(x: 0, y: tail, width: bounds.width, height: bounds.height - tail) }

    func syncGlass() {
        #if compiler(>=6.2)
        guard #available(macOS 26, *) else { return }
        glass?.removeFromSuperview()
        glass = nil
        guard let tint = theme.glassTint else { return }
        let g = GlassBackground(frame: glassFrame)
        g.cornerRadius = 16   // rows are 10 and inset 6, so the corners stay concentric
        g.tintColor = tint
        addSubview(g, positioned: .below, relativeTo: nil)
        glass = g
        #endif
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); glass?.frame = glassFrame }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { onClick?() }
    let tail: CGFloat = 9
    let pad: CGFloat = 6
    /// Ragnarok's window title bar sits above the rows.
    var titleBar: CGFloat { theme.ragnarok ? 18 : 0 }

    /// Lays the rows out top-to-bottom and returns the bubble size.
    func set(rows: [RowView], width: CGFloat) -> NSSize {
        subviews.filter { $0 is RowView }.forEach { $0.removeFromSuperview() }
        let gap: CGFloat = 4
        let inner = rows.reduce(0) { $0 + $1.frame.height } + gap * CGFloat(max(0, rows.count - 1))
        let h = inner + pad * 2 + tail + titleBar
        var y = h - titleBar - pad
        for r in rows {
            y -= r.frame.height
            r.frame.origin = NSPoint(x: pad, y: y)
            addSubview(r)
            y -= gap
        }
        return NSSize(width: width, height: h)
    }

    /// One outline with the tail built into the bottom edge: a separate tail shape leaves the
    /// body's edge drawn across its base and a darker seam where the translucent fills overlap.
    private func outline(_ body: NSRect, radius r: CGFloat, tailHalf w: CGFloat) -> NSBezierPath {
        let mid = bounds.midX
        let path = NSBezierPath()
        path.move(to: NSPoint(x: body.minX + r, y: body.minY))
        path.line(to: NSPoint(x: mid - w, y: body.minY))
        path.line(to: NSPoint(x: mid, y: 1))
        path.line(to: NSPoint(x: mid + w, y: body.minY))
        path.appendArc(from: NSPoint(x: body.maxX, y: body.minY), to: NSPoint(x: body.maxX, y: body.maxY), radius: r)
        path.appendArc(from: NSPoint(x: body.maxX, y: body.maxY), to: NSPoint(x: body.minX, y: body.maxY), radius: r)
        path.appendArc(from: NSPoint(x: body.minX, y: body.maxY), to: NSPoint(x: body.minX, y: body.minY), radius: r)
        path.appendArc(from: NSPoint(x: body.minX, y: body.minY), to: NSPoint(x: mid, y: body.minY), radius: r)
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard glass == nil else { return }
        let body = NSRect(x: 1, y: tail, width: bounds.width - 2, height: bounds.height - tail - 1)
        if theme.ragnarok { drawRagnarokWindow(body); return }
        let path = outline(body, radius: theme.minimal ? 14 : 12, tailHalf: 8)
        theme.bubbleFill.setFill()
        path.fill()
        theme.bubbleStroke.setStroke()
        path.lineWidth = theme.minimal ? 1 : 1.5
        path.stroke()
    }

    /// Grey window with a blue gradient title bar and a white list box, as in Ragnarok Online.
    private func drawRagnarokWindow(_ body: NSRect) {
        let path = outline(body, radius: 4, tailHalf: 7)
        theme.bubbleFill.setFill()
        path.fill()

        let bar = NSRect(x: body.minX, y: body.maxY - titleBar, width: body.width, height: titleBar)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4).addClip()
        NSGradient(colors: [hex(0xb4c3dc), hex(0xa9c4ec), hex(0x8296c6), hex(0x93a3d0), hex(0xb9c6e2)])?.draw(in: bar, angle: 90)
        hex(0x8d9ab8).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Round badge at the left of the title, then the title in white with a dark outline.
        let dot = NSRect(x: bar.minX + 5, y: bar.midY - 4.5, width: 9, height: 9)
        hex(0xf4f6fb).setFill()
        NSBezierPath(ovalIn: dot).fill()
        hex(0x4a5d86).setStroke()
        let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
        hex(0x6c86bd).setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: 3, dy: 3)).fill()
        let font = NSFont.boldSystemFont(ofSize: 11)
        let shade = NSAttributedString(string: "Angeling", attributes: [.font: font, .foregroundColor: hex(0x26324d)])
        let title = NSAttributedString(string: "Angeling", attributes: [.font: font, .foregroundColor: NSColor.white])
        let at = NSPoint(x: dot.maxX + 5, y: bar.midY - title.size().height / 2)
        shade.draw(at: NSPoint(x: at.x + 1, y: at.y - 1))
        title.draw(at: at)

        // White list box behind the rows.
        let list = NSRect(x: body.minX + 3, y: body.minY + 3, width: body.width - 6, height: body.height - titleBar - 6)
        NSColor.white.setFill()
        list.fill()
        hex(0xc8c8c8).setStroke()
        NSBezierPath(rect: list.insetBy(dx: 0.5, dy: 0.5)).stroke()

        theme.bubbleStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// Ragnarok Online emote (animated GIF from iRO wiki) that pops up beside the pet.
final class EmoteView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // never steal clicks
}

let emoteDir = baseDir.appendingPathComponent("emotes")
// Ragnarok level-up jingle (fetched by install.sh); used as the reminder chime when present.
let levelUpSound = baseDir.appendingPathComponent("sounds/levelup.mp3")
func alarmSound(_ name: String) -> NSSound? {
    name == "levelup" ? NSSound(contentsOf: levelUpSound, byReference: false) : (NSSound(named: name)?.copy() as? NSSound)
}
let emoteImages: [String: NSImage] = {
    var m: [String: NSImage] = [:]
    for n in ["lv", "heh", "swt", "wah", "omg", "slur"] {
        if let i = NSImage(contentsOf: emoteDir.appendingPathComponent("\(n).gif")) { m[n] = i }
    }
    return m
}()

// Little red count shown on the pet while the activity bubble is hidden (like Codex's badge).
// Small pill beside the pet that hides / shows the activity bubble.
final class ToggleButton: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var shown = true { didSet { needsDisplay = true; toolTip = shown ? "ซ่อนกิจกรรม" : "แสดงกิจกรรม" } }
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; roCursor = pointerEntered(); onHover?(true) }
    override func mouseExited(with e: NSEvent) { hovering = false; pointerExited(roCursor); onHover?(false) }
    private var roCursor = false

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        if theme.id != "classic" {
            theme.bubbleFill.setFill()
            path.fill()
            if hovering { theme.hover.setFill(); path.fill() }
        } else {
            NSColor(calibratedRed: 1, green: hovering ? 0.9 : 0.97, blue: hovering ? 0.92 : 0.96, alpha: 0.95).setFill()
            path.fill()
        }
        theme.bubbleStroke.setStroke()
        path.lineWidth = 1.2
        path.stroke()
        let name = shown ? "eye.slash" : "text.bubble"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
            let tinted = NSImage(size: img.size, flipped: false) { rect in
                img.draw(in: rect)
                (theme.minimal ? theme.secondary : theme.project).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let sz = tinted.size
            tinted.draw(in: NSRect(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2,
                                   width: sz.width, height: sz.height))
        }
    }
}

final class BadgeView: NSView {
    var count = 0 { didSet { isHidden = count == 0; needsDisplay = true } }
    var color = NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.35, alpha: 1)
    var label: String? { didSet { needsDisplay = true } }   // shown instead of the count
    var text: String { label ?? (count > 999 ? "999+" : "\(count)") }
    /// Circle for one digit, pill for more.
    var width: CGFloat { max(18, ceil(NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 11)]).size().width) + 10) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let r = bounds.insetBy(dx: 1, dy: 1)
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        let s = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white])
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }
}

// MARK: - Pet view (click / drag)

/// Ragnarok Online-style pointer: a folded blue arrowhead that spins about its left edge (tip to bottom).
/// Each frame is a shaded 3D render, drawn here rather than shipped as artwork, so nothing © Gravity is needed.
enum ROCursor {
    static let frames: [NSCursor] = (0..<16).map { cursor(angle: CGFloat($0) / 16 * 2 * .pi) }
    private static var frame = 0

    private struct V { var x, y, z: CGFloat }
    private static func cross(_ a: V, _ b: V) -> V { V(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x) }
    private static func dot(_ a: V, _ b: V) -> CGFloat { a.x * b.x + a.y * b.y + a.z * b.z }

    /// Face colour from how much light it catches: navy in shadow, blue, then white.
    private static func shade(_ b: CGFloat) -> NSColor {
        let stops: [(CGFloat, NSColor)] = [(0, hex(0x2b3f6b)), (0.3, hex(0x4f6aa0)), (0.5, hex(0x678bc6)), (0.68, hex(0xa9bfe6)), (0.8, hex(0xffffff))]
        guard let hi = stops.firstIndex(where: { $0.0 >= b }) else { return stops.last!.1 }
        guard hi > 0 else { return stops[0].1 }
        let (b0, c0) = stops[hi - 1], (b1, c1) = stops[hi]
        return c0.blended(withFraction: (b - b0) / (b1 - b0), of: c1) ?? c1
    }

    private static func cursor(angle: CGFloat) -> NSCursor {
        // Top-left-origin canvas; the spin axis runs from the tip down to the bottom point, so the
        // canvas is wide enough for the arrowhead to swing to either side of it.
        let size = NSSize(width: 52, height: 34), origin = NSPoint(x: 26, y: 2)
        // At angle 0 this is the in-game pose: blue face tip-right-notch, white sliver tip-notch-bottom.
        let bottom = V(x: 1, y: 29, z: 0), right = V(x: 23, y: 20, z: 0), notch = V(x: 7, y: 21, z: 6)
        let len = sqrt(dot(bottom, bottom)), axis = V(x: bottom.x / len, y: bottom.y / len, z: 0)
        func spin(_ v: V) -> V {   // Rodrigues' rotation about the axis through the tip
            let c = cos(angle), s = sin(angle), k = cross(axis, v), d = dot(axis, v) * (1 - c)
            return V(x: v.x * c + k.x * s + axis.x * d, y: v.y * c + k.y * s + axis.y * d, z: v.z * c + k.z * s + axis.z * d)
        }
        let tip = V(x: 0, y: 0, z: 0), r = spin(right), n = spin(notch)
        func pt(_ v: V) -> NSPoint { NSPoint(x: origin.x + v.x, y: origin.y + v.y) }
        let light = { (v: V) -> V in let l = sqrt(dot(v, v)); return V(x: v.x / l, y: v.y / l, z: v.z / l) }(V(x: -0.55, y: -0.35, z: 0.75))
        // Both faces are two-sided; draw the farther one first. The big face stays blue and the
        // sliver stays pale, as in the game, so each keeps its own band of the shading ramp.
        let faces = [([tip, r, n], CGFloat(0), CGFloat(0.6)), ([tip, n, bottom], CGFloat(0.45), CGFloat(1))]
            .sorted { ($0.0[1].z + $0.0[2].z) < ($1.0[1].z + $1.0[2].z) }

        let img = NSImage(size: size, flipped: true) { _ in
            let outline = NSBezierPath()
            outline.move(to: pt(tip)); outline.line(to: pt(r)); outline.line(to: pt(n)); outline.line(to: pt(bottom))
            outline.close()
            outline.lineJoinStyle = .miter
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 1, height: -1)
            shadow.shadowBlurRadius = 1
            shadow.set()
            hex(0x111a26).setFill()
            outline.fill()
            NSGraphicsContext.restoreGraphicsState()
            for (f, lo, hi) in faces {
                var nv = cross(V(x: f[1].x - f[0].x, y: f[1].y - f[0].y, z: f[1].z - f[0].z),
                               V(x: f[2].x - f[0].x, y: f[2].y - f[0].y, z: f[2].z - f[0].z))
                let l = sqrt(dot(nv, nv))
                guard l > 0.01 else { continue }
                nv = V(x: nv.x / l, y: nv.y / l, z: nv.z / l)
                if nv.z < 0 { nv = V(x: -nv.x, y: -nv.y, z: -nv.z) }
                let p = NSBezierPath()
                p.move(to: pt(f[0])); p.line(to: pt(f[1])); p.line(to: pt(f[2])); p.close()
                // Faces turned edge-on to the viewer go dark, so a thin sliver never reads as a hole.
                shade(lo + (hi - lo) * max(0, min(1, dot(nv, light) * (0.35 + 0.65 * nv.z)))).setFill()
                p.fill()
            }
            hex(0x111a26).setStroke()
            outline.lineWidth = 1.1
            outline.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: origin)
    }

    private static var timer: Timer?
    private static var holders = 0

    /// Callers pair enter / exit; the arrow comes back once nothing holds the cursor.
    static func enter() {
        holders += 1
        frames[frame].set()
        guard timer == nil else { return }
        // Each tick shows the next frame, which also wins back the cursor if something else reset it.
        let t = Timer(timeInterval: 0.07, repeats: true) { _ in
            // A view removed while hovered never gets its exit; let go once the pointer leaves our windows.
            let p = NSEvent.mouseLocation
            guard NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(p) }) else { holders = 1; ROCursor.exit(); return }
            frame = (frame + 1) % frames.count
            frames[frame].set()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    static func exit() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
        NSCursor.arrow.set()
    }
}

final class PetView: NSImageView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { ROCursor.enter(); onHover?(true) }
    override func mouseExited(with e: NSEvent) { ROCursor.exit(); onHover?(false) }
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private var downPoint: NSPoint = .zero
    private var winOrigin: NSPoint = .zero
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        downPoint = NSEvent.mouseLocation
        winOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downPoint.x, dy = p.y - downPoint.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: winOrigin.x + dx, y: winOrigin.y + dy))
        onDrag?(e.deltaX)
    }
    override func mouseUp(with e: NSEvent) {
        if dragged { onDragEnd?() } else { onClick?() }
    }
    override func rightMouseDown(with e: NSEvent) {
        if let m = menuProvider?() { NSMenu.popUpContextMenu(m, with: e, for: self) }
    }
}

// MARK: - Controller

final class PetController: NSObject, NSMenuDelegate {
    let petSize = NSSize(width: 67, height: 73)
    let winWidth: CGFloat = 300
    let panel: NSPanel
    let bubble = BubbleView(frame: .zero)
    let pet = PetView(frame: .zero)
    let badge = BadgeView(frame: .zero)
    let lineBadge = BadgeView(frame: .zero)
    var lineUnread = 0
    var lineDismissed: Int?  // unread count when the LINE row was hidden
    let discordBadge = BadgeView(frame: .zero)
    var discordUnread = 0
    var discordDismissed: Int?  // unread count when the Discord row was hidden
    let reminders = ReminderStore()
    lazy var reminderForm: ReminderForm = {
        let f = ReminderForm(store: reminders)
        f.onSaved = { [weak self] in self?.setOverride("waving", for: 1.2); self?.showEmote("heh", for: 2.5); self?.refresh() }
        return f
    }()
    var lastChime: Double = 0
    var latestVersion: String?
    var releasePage: URL?
    var updating = false
    var autoUpdateCheck: Bool { flag("autoUpdateCheck") }
    var updateAvailable: Bool {
        guard let v = latestVersion else { return false }
        return Updater.isNewer(v, than: Updater.current) && v != d.string(forKey: "skippedVersion")
    }
    var reminderSound: String {
        let hasLevelUp = FileManager.default.fileExists(atPath: levelUpSound.path)
        let s = d.string(forKey: "reminderSound") ?? (hasLevelUp ? "levelup" : "Glass")
        return s == "levelup" && !hasLevelUp ? "Glass" : s
    }
    let toggle = ToggleButton(frame: .zero)
    let emote = EmoteView(frame: .zero)
    var emoteName: String?
    var emoteUntil = Date.distantPast
    var prevStates: [String: (String, Double)] = [:]   // session -> (effective state, updated)
    var runningSince: [String: Double] = [:]
    var sweatShown: Set<String> = []
    var lastActive = Date()
    var lastSlur = Date.distantPast
    let angeling: SpriteSheet
    var sheet: Sprite
    var shownCharacter = PetController.characterChoice   // differs from the choice while the menu previews another
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var animName = "idle"
    var frameIndex = 0
    var frameTimer: Timer?
    var overrideAnim: String?       // transient (jumping, dragging)
    var overrideUntil: Date = .distantPast
    var lastPrimaryKey = ""
    var expanded = false
    var sessions: [(SessionState, String)] = []
    var dismissed: [String: Double] = [:]  // session -> updated stamp at dismissal
    var didFirstRefresh = false
    var lastRowsSig = ""
    var bubbleSize = NSSize.zero
    func flag(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
    var showTask: Bool { flag("showTask") }
    var showText: Bool { flag("showText") }
    var showPlan: Bool { flag("showPlan") }
    var showLine: Bool { flag("showLine") }
    var showDiscord: Bool { flag("showDiscord") }

    let d = UserDefaults.standard
    var activityHidden: Bool { get { d.bool(forKey: "activityHidden") } set { d.set(newValue, forKey: "activityHidden") } }
    var petHidden: Bool { get { d.bool(forKey: "petHidden") } set { d.set(newValue, forKey: "petHidden") } }
    var popWhenWaiting: Bool { get { d.object(forKey: "popWhenWaiting") as? Bool ?? true } set { d.set(newValue, forKey: "popWhenWaiting") } }
    var waitSound: Bool { flag("waitSound") }
    var themeChoice: String { ProcessInfo.processInfo.environment["ANGELING_THEME"] ?? d.string(forKey: "theme") ?? "classic" }
    static var characterChoice: String {
        ProcessInfo.processInfo.environment["ANGELING_CHARACTER"] ?? UserDefaults.standard.string(forKey: "character") ?? "angeling"
    }

    /// The chosen character's artwork; Angeling when it is "angeling" or its files are gone.
    static func sprite(_ id: String, angeling: SpriteSheet) -> Sprite {
        if let p = codexPets.first(where: { $0.id == id }), let s = SpriteSheet(url: p.sheetURL) { return s }
        return bomberCharacters.first { $0.id == id }.flatMap { BomberSprite($0) } ?? angeling
    }

    /// Switch to the chosen theme ("auto" follows macOS light / dark, so this runs every refresh).
    func applyTheme() {
        let t = Theme.named(themeChoice)
        guard t.id != theme.id else { return }
        theme = t
        bubble.syncGlass()
        badge.color = t.minimal ? t.alert : NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.35, alpha: 1)
        lineBadge.color = t.line
        discordBadge.color = t.discord
        [badge, lineBadge, discordBadge, toggle, bubble].forEach { $0.needsDisplay = true }
        lastRowsSig = ""   // rebuild the rows in the new colours
    }

    init(sheet: SpriteSheet) {
        angeling = sheet
        self.sheet = PetController.sprite(PetController.characterChoice, angeling: sheet)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 140),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView = content
        pet.imageScaling = .scaleProportionallyUpOrDown
        pet.onClick = { [weak self] in self?.clicked() }
        pet.onDrag = { [weak self] dx in self?.dragging(dx) }
        pet.onDragEnd = { [weak self] in self?.dragEnded() }
        pet.menuProvider = { [weak self] in self?.makeMenu(forStatusBar: false) ?? NSMenu() }
        content.addSubview(bubble)
        content.addSubview(pet)
        content.addSubview(badge)
        content.addSubview(lineBadge)
        lineBadge.color = lineGreen
        lineBadge.toolTip = "LINE ยังไม่อ่าน"
        content.addSubview(discordBadge)
        discordBadge.color = discordBlurple
        discordBadge.toolTip = "Discord ยังไม่อ่าน (DM และ @mention)"
        content.addSubview(toggle)
        bubble.onClick = { [weak self] in self?.clicked() }
        emote.animates = true
        emote.imageScaling = .scaleNone
        emote.isHidden = true
        content.addSubview(emote)
        toggle.onClick = { [weak self] in self?.toggleActivity() }
        // The toggle only appears while the pointer is over the pet (or the toggle itself).
        toggle.isHidden = true
        pet.onHover = { [weak self] on in self?.hover(on) }
        toggle.onHover = { [weak self] on in self?.hover(on) }
        badge.count = 0

        if d.object(forKey: "x") != nil {
            panel.setFrameOrigin(NSPoint(x: d.double(forKey: "x"), y: d.double(forKey: "y")))
        } else if let s = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.maxX - winWidth - 20, y: s.minY + 20))
        }

        // Menu bar icon: the way back when Angeling is tucked away.
        if let b = statusItem.button {
            b.image = statusIcon()
            b.imagePosition = .imageLeading
        }
        let m = NSMenu()
        m.delegate = self
        statusItem.menu = m

        if !petHidden { panel.orderFrontRegardless() }
        play("idle")
        refresh()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        pollLine()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.pollLine() }
        reminders.syncWithCalendar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkForUpdates(manual: false) }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates(manual: false) }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.reminders.syncWithCalendar() }
    }

    /// Polls the LINE and Discord Dock badges (every 3 s, off the main thread).
    func pollLine() {
        let (wantLine, wantDiscord) = (showLine, showDiscord)
        DispatchQueue.global(qos: .utility).async {
            let l = wantLine ? LineWatch.unread() : 0
            let dc = wantDiscord ? DiscordWatch.unread() : 0
            DispatchQueue.main.async { [weak self] in
                guard let self, l != self.lineUnread || dc != self.discordUnread else { return }
                // Something new brings a hidden row back.
                if l > self.lineUnread { self.lineDismissed = nil }
                if dc > self.discordUnread {
                    if self.didFirstRefresh { self.showEmote("heh", for: 2.5) }
                    self.discordDismissed = nil
                }
                (self.lineUnread, self.discordUnread) = (l, dc)
                self.refresh()
            }
        }
    }

    var lineVisible: Bool { showLine && lineUnread > 0 && lineDismissed == nil }
    var discordVisible: Bool { showDiscord && discordUnread > 0 && discordDismissed == nil }

    // MARK: updates

    func checkForUpdates(manual: Bool) {
        guard manual || autoUpdateCheck else { return }
        Updater.fetchLatest { [weak self] v, page in
            guard let self else { return }
            let wasAvailable = self.updateAvailable
            if let v { (self.latestVersion, self.releasePage) = (v, page) }
            if self.updateAvailable && !wasAvailable && !manual { self.showEmote("lv", for: 3) }
            self.refresh()
            guard manual else { return }
            let alert = NSAlert()
            if v == nil {
                alert.messageText = "ตรวจไม่ได้ตอนนี้"
                alert.informativeText = "เชื่อมต่อ GitHub ไม่ได้ ลองใหม่อีกครั้งภายหลัง"
            } else if Updater.isNewer(v!, than: Updater.current) {
                alert.messageText = "มีเวอร์ชันใหม่ \(v!)"
                alert.informativeText = "ตอนนี้ใช้ \(Updater.current) อยู่ อัปเดตเลยไหม?"
                alert.addButton(withTitle: "อัปเดตเลย")
                alert.addButton(withTitle: "ไว้ทีหลัง")
            } else {
                alert.messageText = "ใช้เวอร์ชันล่าสุดอยู่แล้ว"
                alert.informativeText = "Angeling \(Updater.current) (ล่าสุดบน GitHub: \(v!))"
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn && v != nil && Updater.isNewer(v!, than: Updater.current) { self.runUpdate() }
        }
    }

    @objc func checkUpdatesNow() { checkForUpdates(manual: true) }
    @objc func runUpdate() {
        guard !updating else { return }
        updating = true
        setOverride("jumping", for: 1.2)
        refresh()
        Updater.install() // the installer quits this copy and opens the new one
        // Still here after 3 minutes: the update failed (offline, GitHub down, …).
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self, self.updating else { return }
            self.updating = false
            self.refresh()
            let alert = NSAlert()
            alert.messageText = "อัปเดตไม่สำเร็จ"
            alert.informativeText = "ลองใหม่อีกครั้งภายหลัง ดูรายละเอียดได้ที่ ~/.claude/angeling-pet/update.log"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    @objc func openReleasePage() { if let u = releasePage { NSWorkspace.shared.open(u) } }
    @objc func skipVersion() { d.set(latestVersion, forKey: "skippedVersion"); refresh() }
    @objc func toggleAutoUpdateCheck() {
        d.set(!autoUpdateCheck, forKey: "autoUpdateCheck")
        if autoUpdateCheck { checkForUpdates(manual: false) }
    }

    func updateRow(width w: CGFloat) -> RowView {
        let t = rowHeader(icon: "🎁", title: updating ? "กำลังอัปเดตเป็น \(latestVersion ?? "")…" : "มี Angeling เวอร์ชันใหม่ \(latestVersion ?? "")",
                          titleColor: theme.gold, dot: theme.gold, status: "ตอนนี้ \(Updater.current)", statusColor: theme.secondary, width: w)
        t.append(rowLine(updating ? "Angeling จะปิดแล้วเปิดใหม่เองในไม่กี่วินาที" : "คลิกเพื่ออัปเดต · คลิกขวาสำหรับตัวเลือก",
                         size: 11, color: theme.secondary))
        let r = RowView(text: t, width: w, clickable: !updating)
        r.accent = theme.gold
        guard !updating else { return r }
        r.onClick = { [weak self] in self?.runUpdate() }
        r.onRightClick = { [weak self] e in
            let m = NSMenu()
            for (title, sel) in [("อัปเดตเลย", #selector(PetController.runUpdate)), ("ดูว่ามีอะไรใหม่", #selector(PetController.openReleasePage)),
                                 ("ข้ามเวอร์ชันนี้", #selector(PetController.skipVersion))] {
                m.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
            }
            NSMenu.popUpContextMenu(m, with: e, for: r)
        }
        return r
    }

    // MARK: reminders

    func ringing(_ now: Double) -> [Reminder] { reminders.items.filter { $0.alertAt <= now } }
    func upcoming(_ now: Double) -> [Reminder] { reminders.items.filter { $0.alertAt > now && $0.alertAt - now <= 15 * 60 } }

    /// Start ringing reminders whose time has come; chime again once a minute for 5 minutes.
    func checkReminders(_ now: Double) {
        for r in reminders.items where r.alertAt <= now && r.firedAt == nil {
            reminders.update(r.id) { $0.firedAt = now }
            if petHidden { petHidden = false; panel.orderFrontRegardless() }
            setOverride("jumping", for: 1.2)
            showEmote("omg", for: 4)
            chime(3)
        }
        if let latest = ringing(now).compactMap(\.firedAt).max(), now - latest < 300, now - lastChime >= 60 { chime(1) }
    }

    func chime(_ times: Int) {
        lastChime = Date().timeIntervalSince1970
        guard reminderSound != "off", ProcessInfo.processInfo.environment["ANGELING_SNAPSHOT"] == nil else { return }
        let gap = max(1.3, (alarmSound(reminderSound)?.duration ?? 1) + 0.4)
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [weak self] in
                guard let self else { return }
                alarmSound(self.reminderSound)?.play()
            }
        }
    }

    @objc func newReminder() { reminderForm.show() }
    @objc func reminderDone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        reminders.remove(id)
        setOverride("waving", for: 1)
        refresh()
    }
    func reminderDone(id: String) { reminders.remove(id); setOverride("waving", for: 1); showEmote("lv", for: 2.5); refresh() }
    @objc func reminderSnooze(_ sender: NSMenuItem) {
        guard let (id, mins) = sender.representedObject as? (String, Int) else { return }
        reminders.update(id) { $0.snoozedUntil = Date().timeIntervalSince1970 + Double(mins * 60); $0.firedAt = nil }
        refresh()
    }
    @objc func reminderDelete(_ sender: NSMenuItem) {
        guard let (id, withEvent) = sender.representedObject as? (String, Bool) else { return }
        reminders.remove(id, deleteEvent: withEvent)
        refresh()
    }
    @objc func setReminderSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        d.set(name, forKey: "reminderSound")
        chime(1)
    }
    @objc func openCalendarPrivacy() {
        if reminders.accessUndetermined { reminders.requestAccess { _ in } }
        else { Focus.openURL("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") }
    }

    func reminderMenu(_ r: Reminder, ringing: Bool) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ obj: Any) {
            let i = m.addItem(withTitle: title, action: sel, keyEquivalent: "")
            i.target = self
            i.representedObject = obj
        }
        if ringing {
            add("ทำแล้ว ✓", #selector(reminderDone(_:)), r.id)
            for mins in [5, 10, 30, 60] { add("เลื่อนไป \(mins < 60 ? "\(mins) นาที" : "1 ชั่วโมง")", #selector(reminderSnooze(_:)), (r.id, mins)) }
            m.addItem(.separator())
        }
        add("ลบการเตือน (เก็บ event ในปฏิทินไว้)", #selector(reminderDelete(_:)), (r.id, false))
        if r.eventId != nil { add("ลบทั้งการเตือนและ event ในปฏิทิน", #selector(reminderDelete(_:)), (r.id, true)) }
        return m
    }

    // MARK: themed row text

    /// A row's first line. Minimal themes: "● title ⇥ status" with the status right-aligned;
    /// Classic: "icon title  status".
    func rowHeader(icon: String, title: String, titleColor: NSColor, dot: NSColor, status: String, statusColor: NSColor,
                   statusBold: Bool = false, width: CGFloat) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let statusFont = statusBold ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 11)
        if theme.minimal {
            out.append(NSAttributedString(string: dotPrefix, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: dot, .baselineOffset: 1]))
            let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let tabStop = width - 22
            // Shorten a long title so the right-aligned status stays on the same line
            let statusWidth = status.isEmpty ? 0 : ceil(NSAttributedString(string: status, attributes: [.font: statusFont]).size().width) + 10
            let fitted = fit(title, font: titleFont, maxWidth: tabStop - dotIndent - statusWidth)
            out.append(NSAttributedString(string: fitted, attributes: [.font: titleFont, .foregroundColor: theme.text]))
            if !status.isEmpty { out.append(NSAttributedString(string: "\t" + status, attributes: [.font: statusFont, .foregroundColor: statusColor])) }
            let para = NSMutableParagraphStyle()
            para.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
            out.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: out.length))
        } else {
            out.append(NSAttributedString(string: "\(icon) \(title)", attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: titleColor]))
            if !status.isEmpty { out.append(NSAttributedString(string: "  " + status, attributes: [.font: statusFont, .foregroundColor: statusColor])) }
        }
        return out
    }

    /// `s` cut down with a trailing "…" until it fits in `maxWidth` points.
    func fit(_ s: String, font: NSFont, maxWidth: CGFloat) -> String {
        let width = { (t: String) in NSAttributedString(string: t, attributes: [.font: font]).size().width }
        if width(s) <= maxWidth { return s }
        var chars = Array(s)
        while !chars.isEmpty && width(String(chars) + "…") > maxWidth { chars.removeLast() }
        return String(chars) + "…"
    }

    let dotPrefix = "●  "
    /// Width of the dot and its gap, so minimal themes line later lines up under the title.
    lazy var dotIndent: CGFloat = ceil(NSAttributedString(string: dotPrefix, attributes: [.font: NSFont.systemFont(ofSize: 9)]).size().width)

    /// One more line of a row, under its header.
    func rowLine(_ text: String, size: CGFloat = 12, color: NSColor? = nil, bold: Bool = false) -> NSAttributedString {
        var a: [NSAttributedString.Key: Any] = [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                                                .foregroundColor: color ?? theme.text]
        if theme.minimal {
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = dotIndent
            para.headIndent = dotIndent
            a[.paragraphStyle] = para
        }
        return NSAttributedString(string: "\n" + text, attributes: a)
    }

    /// Ringing reminders (orange, stay until handled) and ones due within 15 minutes.
    func reminderRows(width w: CGFloat, ringingOnly: Bool = false) -> [RowView] {
        let now = Date().timeIntervalSince1970
        var rows: [RowView] = []
        for r in ringing(now) {
            let t = rowHeader(icon: "⏰", title: "ถึงเวลาแล้ว!", titleColor: theme.alarm, dot: theme.alarm,
                              status: reminderWhen(r.date), statusColor: theme.secondary, width: w)
            t.append(rowLine(r.title, size: 13, bold: true))
            t.append(rowLine("คลิกเมื่อทำแล้ว · คลิกขวาเพื่อเลื่อน", size: 11, color: theme.secondary))
            let row = RowView(text: t, width: w, clickable: true)
            row.accent = theme.alarm
            row.onClick = { [weak self] in self?.reminderDone(id: r.id) }
            row.onRightClick = { [weak self] e in
                guard let self else { return }
                NSMenu.popUpContextMenu(self.reminderMenu(r, ringing: true), with: e, for: row)
            }
            rows.append(row)
        }
        guard !ringingOnly else { return rows }
        for r in upcoming(now) {
            let mins = Int(ceil((r.alertAt - now) / 60))
            let t = rowHeader(icon: "⏰", title: "อีก \(mins) นาที", titleColor: theme.alarm, dot: theme.alarm,
                              status: reminderWhen(r.alertAt), statusColor: theme.secondary, width: w)
            t.append(rowLine(r.title))
            let row = RowView(text: t, width: w, clickable: true)
            row.toolTip = "คลิกขวาเพื่อลบการเตือน"
            row.onRightClick = { [weak self] e in
                guard let self else { return }
                NSMenu.popUpContextMenu(self.reminderMenu(r, ringing: false), with: e, for: row)
            }
            rows.append(row)
        }
        return rows
    }

    func reminderSignature() -> String {
        let now = Date().timeIntervalSince1970
        return ringing(now).map { "R\($0.id)\($0.title)" }.joined() + "|"
            + upcoming(now).map { "U\($0.id)\($0.title)\(Int(ceil(($0.alertAt - now) / 60)))" }.joined()
    }

    func statusIcon() -> NSImage? {
        guard let f = sheet.frame(row: 0, col: 0) else { return nil }
        let img = NSImage(size: NSSize(width: 20, height: 20))
        img.lockFocus()
        f.draw(in: NSRect(x: 0, y: -1, width: 20, height: 21.6))
        img.unlockFocus()
        return img
    }

    // MARK: animation

    func play(_ name: String) {
        guard name != animName || frameTimer == nil else { return }
        animName = name
        frameIndex = 0
        showFrame()
    }

    func showFrame() {
        frameTimer?.invalidate()
        let a = sheet.anims[animName] ?? sheet.anims["idle"]!
        pet.image = sheet.frame(row: a.row, col: frameIndex)
        let dur = a.durations[frameIndex] / 1000
        frameTimer = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.frameIndex + 1 < a.durations.count {
                self.frameIndex += 1
            } else if a.loops {
                self.frameIndex = 0
            } else {
                self.overrideAnim = nil
                self.refresh()
                return
            }
            self.showFrame()
        }
    }

    func setOverride(_ name: String, for seconds: Double) {
        overrideAnim = name
        overrideUntil = Date().addingTimeInterval(seconds)
        animName = ""
        play(name)
    }

    // MARK: interaction

    /// Clicking Angeling (or the bubble's background) brings up the most recently active Claude session.
    func clicked() {
        setOverride("jumping", for: 1.0)
        openLatest()
        if sessions.allSatisfy({ $0.1 == "idle" }) { showEmote("slur", for: 2.5) }
        refresh()
    }

    func dragging(_ dx: CGFloat) {
        let name = dx >= 0 ? "running-right" : "running-left"
        overrideAnim = name
        overrideUntil = .distantFuture
        play(name)
    }

    func dragEnded() {
        overrideAnim = nil
        let o = panel.frame.origin
        d.set(o.x, forKey: "x")
        d.set(o.y, forKey: "y")
        refresh()
    }

    func openLatest() {
        // Prefer the newest session that is still working (or waiting on you); else the newest of all.
        let latest = { (xs: [SessionState]) in xs.max(by: { ($0.updated ?? 0) < ($1.updated ?? 0) }) }
        let active = sessions.filter { ["running", "review", "waiting", "failed"].contains($0.1) }.map { $0.0 }
        if let s = latest(active) ?? latest(sessions.map { $0.0 }) {
            Focus.open(s)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openSession(_ s: SessionState) {
        setOverride("waving", for: 0.8)
        Focus.open(s)
    }

    func dismiss(_ s: SessionState) {
        if let id = s.session { dismissed[id] = s.updated ?? 0 }
        refresh()
    }

    // Menus: the pet's right-click menu and the menu bar menu share items.
    func makeMenu(forStatusBar: Bool) -> NSMenu {
        let m = NSMenu()
        func item(_ title: String, _ sel: Selector, on: Bool = false, key: String = "") {
            let i = m.addItem(withTitle: title, action: sel, keyEquivalent: key)
            i.target = self
            i.state = on ? .on : .off
        }
        if forStatusBar {
            let live = visibleSessions()
            if live.isEmpty {
                m.addItem(withTitle: "ยังไม่มี session", action: nil, keyEquivalent: "").isEnabled = false
            }
            for (s, st) in live {
                let i = m.addItem(withTitle: "\(icons[st] ?? "") \(s.project ?? "?") — \(statusLabel[st] ?? "")",
                                  action: #selector(menuOpenSession(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = s.session
                i.toolTip = s.text
            }
            m.addItem(.separator())
            item(petHidden ? "แสดง Angeling" : "ซ่อน Angeling", #selector(togglePet))
        } else {
            item(expanded ? "ย่อรายการ" : "ดูทุก session", #selector(toggleExpand))
        }
        if updateAvailable && !updating {
            item("🎁 อัปเดตเป็นเวอร์ชัน \(latestVersion ?? "")", #selector(runUpdate))
            m.addItem(.separator())
        }
        item("⏰ ตั้งเตือน… (⌥⌘R)", #selector(newReminder))
        let list = NSMenu()
        if reminders.items.isEmpty {
            list.addItem(withTitle: "ยังไม่มีการเตือน", action: nil, keyEquivalent: "").isEnabled = false
        }
        let now = Date().timeIntervalSince1970
        for r in reminders.items {
            let i = list.addItem(withTitle: "\(reminderWhen(r.alertAt)) — \(r.title)", action: nil, keyEquivalent: "")
            i.submenu = reminderMenu(r, ringing: r.alertAt <= now)
        }
        m.addItem(withTitle: "การเตือนที่ตั้งไว้ (\(reminders.items.count))", action: nil, keyEquivalent: "").submenu = list
        let sounds = NSMenu()
        var choices = [("Glass", "Glass"), ("Ping", "Ping"), ("Hero", "Hero"), ("Submarine", "Submarine"), ("Funk", "Funk"), ("ปิดเสียง", "off")]
        if FileManager.default.fileExists(atPath: levelUpSound.path) { choices.insert(("Level Up (Ragnarok)", "levelup"), at: 0) }
        for (title, name) in choices {
            let i = sounds.addItem(withTitle: title, action: #selector(setReminderSound(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = name; i.state = reminderSound == name ? .on : .off
        }
        m.addItem(withTitle: "เสียงเตือน", action: nil, keyEquivalent: "").submenu = sounds
        if !reminders.calendarAccess { item("ให้สิทธิ์ปฏิทิน…", #selector(openCalendarPrivacy)) }
        m.addItem(.separator())
        item(activityHidden ? "แสดงกิจกรรม" : "ซ่อนกิจกรรม", #selector(toggleActivity))
        if !forStatusBar { item("ซ่อน Angeling (⌥⌘A)", #selector(togglePet)) }
        let opts = NSMenu()
        for (title, key) in [("งานที่สั่ง (prompt)", "showTask"), ("ข้อความล่าสุด / สิ่งที่กำลังทำ", "showText"), ("Task list", "showPlan")] {
            let i = opts.addItem(withTitle: title, action: #selector(toggleShow(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = key; i.state = flag(key) ? .on : .off
        }
        m.addItem(withTitle: "แสดงในบับเบิล", action: nil, keyEquivalent: "").submenu = opts
        let themes = NSMenu()
        for (id, title) in Theme.choices {
            let i = themes.addItem(withTitle: title, action: #selector(setTheme(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = id; i.state = themeChoice == id ? .on : .off
        }
        m.addItem(withTitle: "ธีม", action: nil, keyEquivalent: "").submenu = themes
        if !bomberCharacters.isEmpty || !codexPets.isEmpty {
            let chars = NSMenu()
            chars.delegate = self
            // Angeling and the other Codex pets, then the Bomber characters.
            for group in [[("angeling", "Angeling")] + codexPets.map({ ($0.id, $0.displayName) }), bomberCharacters.map({ ($0.id, $0.name) })] where !group.isEmpty {
                if chars.numberOfItems > 0 { chars.addItem(.separator()) }
                for (id, title) in group {
                    let i = chars.addItem(withTitle: title, action: #selector(setCharacter(_:)), keyEquivalent: "")
                    i.target = self; i.representedObject = id; i.state = PetController.characterChoice == id ? .on : .off
                }
            }
            m.addItem(withTitle: "ตัวละคร", action: nil, keyEquivalent: "").submenu = chars
        }
        item("โผล่ออกมาเมื่อมีงานที่ต้องดู", #selector(togglePop), on: popWhenWaiting)
        item("เสียงเตือนเมื่อมีงานที่ต้องดู", #selector(toggleWaitSound), on: waitSound)
        item("แจ้งเตือน LINE", #selector(toggleLine), on: showLine)
        item("แจ้งเตือน Discord", #selector(toggleDiscord), on: showDiscord)
        item("ล้าง session ที่เสร็จแล้ว", #selector(clearDone))
        m.addItem(.separator())
        let upd = NSMenu()
        upd.addItem(withTitle: "Angeling \(Updater.current)", action: nil, keyEquivalent: "").isEnabled = false
        upd.addItem(withTitle: "ตรวจหาเวอร์ชันใหม่ตอนนี้", action: #selector(checkUpdatesNow), keyEquivalent: "").target = self
        let auto = upd.addItem(withTitle: "ตรวจอัตโนมัติ (ทุก 6 ชั่วโมง)", action: #selector(toggleAutoUpdateCheck), keyEquivalent: "")
        auto.target = self
        auto.state = autoUpdateCheck ? .on : .off
        m.addItem(withTitle: "อัปเดต", action: nil, keyEquivalent: "").submenu = upd
        item("ปิด Angeling", #selector(quit))
        return m
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        for i in makeMenu(forStatusBar: true).items { i.menu?.removeItem(i); menu.addItem(i) }
    }

    // The ตัวละคร submenu: hovering a character shows it, leaving goes back to the saved one.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu !== statusItem.menu else { return }
        showCharacter(item?.representedObject as? String ?? PetController.characterChoice)
    }
    func menuDidClose(_ menu: NSMenu) {
        if menu !== statusItem.menu { showCharacter(PetController.characterChoice) }
    }
    func showCharacter(_ id: String) {
        guard id != shownCharacter else { return }
        shownCharacter = id
        sheet = PetController.sprite(id, angeling: angeling)
        frameIndex = 0   // characters differ in frame counts
        showFrame()
    }

    @objc func menuOpenSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let s = sessions.first(where: { $0.0.session == id })?.0 else { return }
        openSession(s)
    }
    @objc func toggleExpand() { expanded.toggle(); activityHidden = false; refresh() }
    var hoverHide: DispatchWorkItem?
    func hover(_ on: Bool) {
        hoverHide?.cancel()
        if on { toggle.isHidden = false; return }
        let w = DispatchWorkItem { [weak self] in self?.toggle.isHidden = true }
        hoverHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w) // time to move onto the toggle
    }

    @objc func toggleActivity() { activityHidden.toggle(); expanded = false; refresh() }
    @objc func togglePet() {
        petHidden.toggle()
        if petHidden { panel.orderOut(nil) } else { panel.orderFrontRegardless(); setOverride("waving", for: 1.2) }
        refresh()
    }
    @objc func toggleShow(_ sender: NSMenuItem) {
        guard let k = sender.representedObject as? String else { return }
        d.set(!flag(k), forKey: k)
        refresh()
    }
    @objc func togglePop() { popWhenWaiting.toggle(); refresh() }
    @objc func setTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        d.set(id, forKey: "theme")
        refresh()
    }
    @objc func setCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        d.set(id, forKey: "character")
        showCharacter(id)
        statusItem.button?.image = statusIcon()
        setOverride("waving", for: 1.2)
    }
    @objc func toggleWaitSound() { d.set(!waitSound, forKey: "waitSound") }
    @objc func toggleLine() { d.set(!showLine, forKey: "showLine"); lineDismissed = nil; pollLine(); refresh() }
    @objc func openLine() { setOverride("waving", for: 0.8); LineWatch.open() }
    @objc func dismissLine() { lineDismissed = lineUnread; refresh() }
    @objc func toggleDiscord() { d.set(!showDiscord, forKey: "showDiscord"); discordDismissed = nil; pollLine(); refresh() }
    @objc func openDiscord() { setOverride("waving", for: 0.8); DiscordWatch.open() }
    @objc func dismissDiscord() { discordDismissed = discordUnread; refresh() }
    @objc func clearDone() {
        let now = Date().timeIntervalSince1970
        for s in loadSessions() where ["done", "idle"].contains(effective(s, now: now)) {
            if let id = s.session { try? FileManager.default.removeItem(at: stateDir.appendingPathComponent("\(id).json")) }
        }
        refresh()
    }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: state -> view

    func visibleSessions() -> [(SessionState, String)] {
        sessions.filter { s, st in
            if st == "idle" { return false }
            guard let id = s.session, let stamp = dismissed[id] else { return true }
            return (s.updated ?? 0) > stamp
        }
    }

    func refresh() {
        applyTheme()
        let now = Date().timeIntervalSince1970
        let previouslyWaiting = Set(sessions.filter { $0.1 == "waiting" }.compactMap { $0.0.session })
        sessions = loadSessions().map { ($0, effective($0, now: now)) }
            .sorted { a, b in
                priority(a.1) != priority(b.1) ? priority(a.1) > priority(b.1) : (a.0.updated ?? 0) > (b.0.updated ?? 0)
            }
        let live = visibleSessions()
        let primary = live.first
        checkReminders(now)

        // A tucked-away Angeling pops back out when a session starts waiting on you.
        let newlyWaiting = live.contains { $0.1 == "waiting" && !previouslyWaiting.contains($0.0.session ?? "") }
        if petHidden && popWhenWaiting && newlyWaiting && didFirstRefresh {
            petHidden = false
            panel.orderFrontRegardless()
        }
        if newlyWaiting && didFirstRefresh && waitSound && ProcessInfo.processInfo.environment["ANGELING_SNAPSHOT"] == nil {
            alarmSound("Funk")?.play()
        }

        // Pet animation
        if let o = overrideAnim, Date() < overrideUntil {
            play(o)
        } else if !ringing(now).isEmpty {
            overrideAnim = nil
            play("waving")
        } else {
            overrideAnim = nil
            var st = primary?.1 ?? "idle"
            let key = "\(primary?.0.session ?? "")|\(primary?.0.state ?? "")|\(primary?.0.updated ?? 0)"
            if st == "done" {
                // Celebrate on arrival, then wave for a bit, then rest.
                if key != lastPrimaryKey && lastPrimaryKey != "" { lastPrimaryKey = key; setOverride("jumping", for: 1.2); layout(live); return }
                let age = now - (primary?.0.updated ?? 0)
                st = age < 8 ? "waving" : "idle"
            }
            lastPrimaryKey = key
            play(st)
        }
        updateEmote(live, now: now)
        didFirstRefresh = true
        layout(live)
    }

    // MARK: emotes
    //   /heh  got a new task        /lv   task finished       /wah  needs your input (stays)
    //   /omg  a tool failed         /swt  still grinding after 5 min
    //   /slur nothing to do for a while (or poked while idle) — hungry for work

    func showEmote(_ name: String, for seconds: Double) {
        guard let img = emoteImages[name] else { return }
        if emoteName != name {
            emoteName = name
            emote.image = img
        }
        emoteUntil = Date().addingTimeInterval(seconds)
        emote.isHidden = false
        placeEmote()
    }

    func placeEmote() { layout(visibleSessions()) }

    func updateEmote(_ live: [(SessionState, String)], now: Double) {
        var pick: (String, Double, Int)?   // name, seconds, priority
        func offer(_ n: String, _ secs: Double, _ pr: Int) { if pick == nil || pr > pick!.2 { pick = (n, secs, pr) } }

        for (s, st) in sessions {
            guard let id = s.session else { continue }
            let prev = prevStates[id]
            let updated = s.updated ?? 0
            if didFirstRefresh, prev?.0 != st || (st == "running" && s.text == "รับงานแล้ว!" && prev?.1 != updated) {
                switch st {
                case "waiting": offer("wah", 4, 5)
                case "failed": offer("omg", 3, 4)
                case "done": offer("lv", 4, 3)
                case "running", "review":
                    if prev == nil || ["idle", "done"].contains(prev!.0) || s.text == "รับงานแล้ว!" { offer("heh", 3, 2) }
                default: break
                }
            }
            // Track continuous work for the sweat drop.
            if st == "running" || st == "review" {
                if runningSince[id] == nil || !["running", "review"].contains(prev?.0 ?? "") {
                    runningSince[id] = now; sweatShown.remove(id)
                }
                if let t0 = runningSince[id], now - t0 > 300, !sweatShown.contains(id) {
                    sweatShown.insert(id); offer("swt", 3, 1)
                }
            } else {
                runningSince[id] = nil
            }
            prevStates[id] = (st, updated)
        }

        let busy = live.contains { ["running", "review", "waiting", "failed"].contains($0.1) }
        if busy { lastActive = Date() }
        // Bored: nothing happening for 10 min -> drool now and then.
        if !busy, Date().timeIntervalSince(lastActive) > 600, Date().timeIntervalSince(lastSlur) > 600 {
            lastSlur = Date(); offer("slur", 3, 0)
        }

        if let p = pick { showEmote(p.0, for: p.1) }
        else if Date() > emoteUntil {
            // Keep calling for help while someone is waiting on you.
            if !ringing(now).isEmpty { showEmote("omg", for: 1) }
            else if live.first?.1 == "waiting" { showEmote("wah", for: 1) }
            else if !emote.isHidden { emote.isHidden = true; emoteName = nil; emote.image = nil; placeEmote() }
        }
    }

    func layout(_ live: [(SessionState, String)]) {
        guard !petHidden else { return }
        // Rebuilding every tick would swallow clicks and hover, so only rebuild on change.
        // A hidden bubble still shows ringing reminders and, unless turned off, sessions that need you.
        let waiting = live.filter { $0.1 == "waiting" }
        let urgent = popWhenWaiting ? waiting : []
        let sig = activityHidden ? "hidden|" + reminderSignature() + "|" + rowsSignature(urgent) : rowsSignature(live)
        if sig != lastRowsSig {
            lastRowsSig = sig
            let rows = activityHidden ? reminderRows(width: winWidth - bubble.pad * 2, ringingOnly: true) + makeRows(urgent, urgentOnly: true)
                                      : makeRows(live)
            bubbleSize = rows.isEmpty ? .zero : bubble.set(rows: rows, width: winWidth)
        }
        let showBubble = bubbleSize != .zero
        bubble.isHidden = !showBubble
        // "!" whenever a session needs you; otherwise the active count while the bubble is hidden.
        let active = live.filter { ["failed", "running", "review"].contains($0.1) }.count
        badge.label = waiting.isEmpty ? nil : "!"
        badge.count = !waiting.isEmpty ? waiting.count : activityHidden ? active : 0
        // Menu bar: the same number as the badge, shown even while the bubble is open.
        let count = waiting.isEmpty ? active : waiting.count
        statusItem.button?.title = count > 0 ? " \(count)" : ""

        // Emote floats above the head (like in RO); the bubble moves up to make room for it.
        var emoteRect = NSRect.zero
        if !emote.isHidden, let img = emote.image {
            let sz = img.size
            let petX = (winWidth - petSize.width) / 2
            emoteRect = NSRect(x: round(petX + petSize.width / 2 - sz.width / 2 - 12), y: petSize.height - 12,
                               width: sz.width, height: sz.height)
        }
        let bubbleY = max(petSize.height - 4, emoteRect.maxY - 12)
        let h = showBubble ? bubbleY + bubbleSize.height : max(petSize.height, emoteRect.maxY)
        var f = panel.frame
        if f.height != h || f.width != winWidth {
            f.size = NSSize(width: winWidth, height: h) // origin (bottom) stays put, grows upward
            panel.setFrame(f, display: true)
        }
        keepOnScreen()
        pet.frame = NSRect(x: (winWidth - petSize.width) / 2, y: 0, width: petSize.width, height: petSize.height)
        badge.frame = NSRect(x: pet.frame.maxX - 16, y: pet.frame.maxY - 22, width: 18, height: 18)
        lineBadge.count = activityHidden && showLine ? lineUnread : 0
        lineBadge.frame = NSRect(x: pet.frame.minX - lineBadge.width + 16, y: pet.frame.maxY - 22, width: lineBadge.width, height: 18)
        discordBadge.count = activityHidden && showDiscord ? discordUnread : 0
        let discordY = lineBadge.count > 0 ? pet.frame.maxY - 42 : pet.frame.maxY - 22  // stacks under LINE's
        discordBadge.frame = NSRect(x: pet.frame.minX - discordBadge.width + 16, y: discordY, width: discordBadge.width, height: 18)
        toggle.frame = NSRect(x: pet.frame.minX - 32, y: 22, width: 28, height: 22)
        toggle.shown = !activityHidden
        emote.frame = emoteRect
        if showBubble {
            bubble.frame = NSRect(x: 0, y: bubbleY, width: bubbleSize.width, height: bubbleSize.height)
            bubble.needsDisplay = true
        }
    }

    func rowsSignature(_ live: [(SessionState, String)]) -> String {
        let now = Date().timeIntervalSince1970
        let idleQuiet = live.first.map { $0.1 == "idle" && now - ($0.0.updated ?? 0) > 60 } ?? true
        let lineSig = (updateAvailable ? "U\(latestVersion ?? "")\(updating)" : "")
            + (lineVisible ? "L\(lineUnread)" : "-")
            + (discordVisible ? "|D\(discordUnread)" : "")
        return "\(expanded)|\(showTask)\(showText)\(showPlan)|\(idleQuiet)|\(lineSig)|\(reminderSignature())|" + live.map { s, st in
            "\(s.session ?? "")\(st)\(s.updated ?? 0)"
        }.joined(separator: ",")
    }

    /// Clamp the window into the visible area of whichever screen holds the pet.
    func keepOnScreen() {
        var f = panel.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: f.midX, y: f.minY + 50)) } ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return }
        f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
        f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
        if f.origin != panel.frame.origin { panel.setFrameOrigin(f.origin) }
    }

    func makeRows(_ live: [(SessionState, String)], urgentOnly: Bool = false) -> [RowView] {
        let w = winWidth - bubble.pad * 2
        let normal = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.text]
        let dim = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.secondary]

        func rowText(_ s: SessionState, _ st: String, detailed: Bool) -> NSAttributedString {
            var status = statusLabel[st] ?? ""
            if let plan = s.plan, !plan.isEmpty { status += " · \(plan.filter { $0.s == "completed" }.count)/\(plan.count)" }
            let statusColor = ["waiting", "done"].contains(st) || (theme.minimal && st == "failed") ? theme.color(st) : theme.secondary
            let out = rowHeader(icon: icons[st] ?? "", title: s.project ?? "?", titleColor: theme.project, dot: theme.color(st),
                                status: status, statusColor: statusColor, statusBold: ["waiting", "done"].contains(st), width: w)
            if detailed && showTask, let t = s.task, !t.isEmpty { out.append(rowLine("งาน: \(t)", size: 11, color: theme.secondary)) }
            if showText, let t = s.text, !t.isEmpty { out.append(rowLine(t)) }
            if detailed && showPlan, let plan = s.plan, !plan.isEmpty {
                for p in plan {
                    let mark = p.s == "completed" ? "✓" : (p.s == "in_progress" ? "▸" : "○")
                    out.append(rowLine("  \(mark) \(p.c)", size: p.s == "in_progress" ? 12 : 11,
                                       color: p.s == "in_progress" ? theme.text : theme.secondary))
                }
            }
            return out
        }

        func sessionRow(_ s: SessionState, _ st: String, detailed: Bool) -> RowView {
            let r = RowView(text: rowText(s, st, detailed: detailed), width: w, clickable: true)
            r.toolTip = "คลิกเพื่อไปที่ session นี้ · คลิกขวาเพื่อซ่อนแถวนี้"
            if st == "done" {
                // Minimal themes mark a finished row with its green dot alone.
                if !theme.minimal { r.accent = theme.done }
                r.onClick = { [weak self] in self?.openSession(s); self?.dismiss(s) }
            } else if st == "waiting" {
                r.accent = theme.alert
                r.pulse = true
                r.toolTip = "Claude รอคุณอยู่ คลิกเพื่อไปตอบ"
                r.onClick = { [weak self] in self?.openSession(s) }
            } else {
                r.onClick = { [weak self] in self?.openSession(s) }
            }
            r.onRightClick = { [weak self] e in
                let m = NSMenu()
                let open = m.addItem(withTitle: "ไปที่ session นี้", action: #selector(PetController.rowMenuOpen(_:)), keyEquivalent: "")
                open.target = self; open.representedObject = s.session
                let hide = m.addItem(withTitle: "ซ่อนแถวนี้", action: #selector(PetController.rowMenuDismiss(_:)), keyEquivalent: "")
                hide.target = self; hide.representedObject = s.session
                m.addItem(.separator())
                m.addItem(withTitle: "แสดงในบับเบิล", action: nil, keyEquivalent: "").isEnabled = false
                for (title, key) in [("งานที่สั่ง (prompt)", "showTask"), ("ข้อความล่าสุด / สิ่งที่กำลังทำ", "showText"), ("Task list", "showPlan")] {
                    let i = m.addItem(withTitle: title, action: #selector(PetController.toggleShow(_:)), keyEquivalent: "")
                    i.target = self; i.representedObject = key; i.state = (self?.flag(key) ?? true) ? .on : .off
                    i.indentationLevel = 1
                }
                NSMenu.popUpContextMenu(m, with: e, for: r)
            }
            return r
        }

        func lineRow() -> RowView {
            let out = rowHeader(icon: "💬", title: "LINE", titleColor: theme.line, dot: theme.line,
                                status: "ยังไม่อ่าน \(lineUnread) ข้อความ", statusColor: theme.secondary, width: w)
            let r = RowView(text: out, width: w, clickable: true)
            r.accent = theme.line
            r.toolTip = "คลิกเพื่อเปิด LINE · คลิกขวาเพื่อซ่อน"
            r.onClick = { [weak self] in self?.openLine() }
            r.onRightClick = { [weak self] e in
                let m = NSMenu()
                for (title, sel) in [("เปิด LINE", #selector(PetController.openLine)), ("ซ่อนจนกว่าจะมีข้อความใหม่", #selector(PetController.dismissLine)),
                                     ("ปิดแจ้งเตือน LINE", #selector(PetController.toggleLine))] {
                    m.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
                }
                NSMenu.popUpContextMenu(m, with: e, for: r)
            }
            return r
        }
        func discordRow() -> RowView {
            let out = rowHeader(icon: "🎮", title: "Discord", titleColor: theme.discord, dot: theme.discord,
                                status: "ยังไม่อ่าน \(discordUnread) ข้อความ", statusColor: theme.secondary, width: w)
            if !theme.minimal { out.append(NSAttributedString(string: " (DM / @mention)", attributes: dim)) }
            let r = RowView(text: out, width: w, clickable: true)
            r.accent = theme.discord
            r.toolTip = "คลิกเพื่อเปิด Discord · คลิกขวาเพื่อซ่อน"
            r.onClick = { [weak self] in self?.openDiscord() }
            r.onRightClick = { [weak self] e in
                let m = NSMenu()
                for (title, sel) in [("เปิด Discord", #selector(PetController.openDiscord)), ("ซ่อนจนกว่าจะมีข้อความใหม่", #selector(PetController.dismissDiscord)),
                                     ("ปิดแจ้งเตือน Discord", #selector(PetController.toggleDiscord))] {
                    m.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
                }
                NSMenu.popUpContextMenu(m, with: e, for: r)
            }
            return r
        }
        // Sessions that need you go above everything else, every one of them.
        let waiting = live.filter { $0.1 == "waiting" }
        if urgentOnly { return waiting.map { sessionRow($0.0, $0.1, detailed: false) } }
        let lineRows = reminderRows(width: w) + (updateAvailable ? [updateRow(width: w)] : []) + (lineVisible ? [lineRow()] : []) + (discordVisible ? [discordRow()] : [])

        if expanded {
            if live.isEmpty && lineRows.isEmpty {
                return [RowView(text: NSAttributedString(string: "ยังไม่มีงานที่กำลังทำ~", attributes: normal), width: w, clickable: false)]
            }
            return waiting.map { sessionRow($0.0, $0.1, detailed: true) } + lineRows
                + live.filter { $0.1 != "waiting" }.map { sessionRow($0.0, $0.1, detailed: true) }
        }

        let activeStates = ["running", "review", "failed"]
        let active = live.filter { activeStates.contains($0.1) }
        let finished = live.filter { $0.1 == "done" }
        var rows: [RowView] = waiting.map { sessionRow($0.0, $0.1, detailed: false) } + lineRows
        if waiting.isEmpty, let (s, st) = active.first {
            rows.append(sessionRow(s, st, detailed: false))
        }
        // Finished tasks stay listed in green until opened, dismissed, or 30 min old.
        rows += finished.prefix(3).map { sessionRow($0.0, $0.1, detailed: false) }
        if finished.count > 3 {
            let more = RowView(text: NSAttributedString(string: "+\(finished.count - 3) งานเสร็จแล้ว  ▾", attributes: dim), width: w, clickable: true)
            more.onClick = { [weak self] in self?.toggleExpand() }
            rows.append(more)
        }
        let others = waiting.isEmpty ? Array(active.dropFirst()) : active
        if !others.isEmpty {
            let more = RowView(text: NSAttributedString(string: "+\(others.count) session กำลังทำงาน  ▾", attributes: dim),
                               width: w, clickable: true)
            more.onClick = { [weak self] in self?.toggleExpand() }
            rows.append(more)
        }
        return rows
    }

    @objc func rowMenuOpen(_ sender: NSMenuItem) { menuOpenSession(sender) }
    @objc func rowMenuDismiss(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let s = sessions.first(where: { $0.0.session == id })?.0 else { return }
        dismiss(s)
    }
}

// MARK: - Global hotkeys ⌥⌘A / ⌥⌘R (Carbon; needs no Accessibility permission)

var hotKeyRefs: [EventHotKeyRef?] = []
var hotKeyActions: [UInt32: () -> Void] = [:]
func registerHotKeys(_ keys: [(Int, () -> Void)]) {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
        hotKeyActions[hk.id]?()
        return noErr
    }, 1, &spec, nil, nil)
    for (i, (code, action)) in keys.enumerated() {
        let id = UInt32(i + 1)
        hotKeyActions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(code), UInt32(cmdKey | optionKey), EventHotKeyID(signature: OSType(0x414E474C), id: id), // 'ANGL'
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }
}

// MARK: - App entry

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
guard let sheet = SpriteSheet(url: baseDir.appendingPathComponent("spritesheet.webp")) else {
    FileHandle.standardError.write("Cannot load spritesheet.webp\n".data(using: .utf8)!)
    exit(1)
}
let controller = PetController(sheet: sheet)
registerHotKeys([(kVK_ANSI_A, { controller.togglePet() }), (kVK_ANSI_R, { controller.newReminder() })])

// Debug: ANGELING_UPDATE_NOW=1 starts an update right away (pair with ANGELING_UPDATE_CMD).
if ProcessInfo.processInfo.environment["ANGELING_UPDATE_NOW"] != nil { controller.runUpdate() }

// Debug: ANGELING_SNAPSHOT=/path.png renders the window to a PNG after a moment, then quits.
if let snap = ProcessInfo.processInfo.environment["ANGELING_SNAPSHOT"] {
    let env = ProcessInfo.processInfo.environment
    let savedActivity = controller.activityHidden, savedPet = controller.petHidden
    controller.petHidden = false
    controller.activityHidden = env["ANGELING_HIDE_ACTIVITY"] != nil
    if env["ANGELING_EXPANDED"] != nil { controller.expanded = true }
    controller.lineUnread = LineWatch.unread()
    controller.discordUnread = DiscordWatch.unread()
    controller.refresh()
    if env["ANGELING_HOVER"] != nil { controller.toggle.isHidden = false }
    if let e = env["ANGELING_EMOTE"] { controller.showEmote(e, for: 10) }
    if let a = env["ANGELING_ANIM"] { controller.setOverride(a, for: 10) }
    if env["ANGELING_LATEST_VERSION"] != nil || env["ANGELING_FAKE_VERSION"] != nil { controller.checkForUpdates(manual: false) }
    if env["ANGELING_FORM"] != nil { controller.reminderForm.window.appearance = NSAppearance(named: .aqua); controller.reminderForm.show(); controller.reminderForm.titleField.stringValue = "ประชุมทีม" }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let v = env["ANGELING_FORM"] != nil ? controller.reminderForm.window.contentView! : controller.panel.contentView!
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            let bg = NSImage(size: v.bounds.size)
            bg.lockFocus()
            (env["ANGELING_FORM"] != nil ? NSColor.windowBackgroundColor : NSColor(calibratedWhite: 0.35, alpha: 1)).setFill(); v.bounds.fill()
            rep.draw(in: v.bounds)
            bg.unlockFocus()
            if let t = bg.tiffRepresentation, let b = NSBitmapImageRep(data: t),
               let png = b.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: snap))
            }
        }
        controller.activityHidden = savedActivity
        controller.petHidden = savedPet
        exit(0)
    }
}
app.run()
