// BackbotBar — a tiny native menu bar app for backbot.
// Shows last-backup status and quick actions. No dependencies; pure Cocoa.
// Build: see build.sh (compiles into BackbotBar.app, an LSUIElement agent).
//
// Autostart is a real Login Item (SMAppService), not a launchd plist, so it
// shows up in System Settings › General › Login Items & Extensions under the
// app's own name and icon rather than as an anonymous background executable.

import Cocoa
import ServiceManagement

let HOME = FileManager.default.homeDirectoryForCurrentUser
let LOG_DIR = HOME.appendingPathComponent(".local/share/backbot/logs")
let BACKBOT = HOME.appendingPathComponent(".local/bin/backbot").path

struct BackupState { var status: String; var when: String; var snap: String }

// ── Login item ───────────────────────────────────────────────────────────
enum LoginItem {
    /// Set once we've registered, so that turning the login item off in System
    /// Settings sticks instead of being switched back on at the next launch.
    private static let didRegisterKey = "didRegisterLoginItem"

    static func registerIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didRegisterKey) else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: didRegisterKey)
        } catch {
            NSLog("backbot: could not register login item: \(error.localizedDescription)")
        }
    }

    static func register() throws {
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: didRegisterKey)
    }

    static func unregister() throws {
        try SMAppService.mainApp.unregister()
        UserDefaults.standard.set(false, forKey: didRegisterKey)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var spinner: Timer?
    var spinPhase: CGFloat = 0
    var backupRunning = false

    func applicationDidFinishLaunching(_ note: Notification) {
        LoginItem.registerIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Persist the user's chosen slot across launches: ⌘-drag it out from behind
        // the notch once and macOS remembers the position forever.
        statusItem.autosaveName = "BackbotBar"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // ── State ────────────────────────────────────────────────────────────
    func latestLog() -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: LOG_DIR,
                includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return files
            .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "log" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }.first
    }

    func resticRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "restic backup"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func readState() -> BackupState {
        guard let log = latestLog(),
              let content = try? String(contentsOf: log, encoding: .utf8) else {
            return BackupState(status: "none", when: "", snap: "")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: log.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let df = DateFormatter(); df.dateFormat = "MMM d, h:mm a"
        let when = df.string(from: date)

        var snap = ""
        if let r = content.range(of: "snapshot [a-f0-9]+ saved", options: .regularExpression) {
            snap = content[r].replacingOccurrences(of: "snapshot ", with: "")
                              .replacingOccurrences(of: " saved", with: "")
        }
        var status = "partial"
        if content.contains("FAILED") { status = "failed" }
        else if content.contains("Warning: at least one source file could not be read") { status = "warnings" }
        else if !snap.isEmpty { status = "ok" }
        return BackupState(status: status, when: when, snap: snap)
    }

    // ── Render ───────────────────────────────────────────────────────────
    func refresh() {
        let running = backupRunning || resticRunning()
        let st = readState()

        // The bot mark, drawn as a template image so it adapts to the menu bar
        // appearance (black in Light mode, white in Dark). No colour except red
        // for an actual failure, so it stays clean and light.
        var badge: BackbotBadge = .none
        var tint: NSColor? = nil
        if running { badge = .running(phase: spinPhase) }
        else if st.status == "failed" { badge = .failed; tint = .systemRed }
        else if st.status == "ok" || st.status == "warnings" { badge = .ok }

        if let btn = statusItem.button {
            btn.image = BackbotMark.statusImage(pointSize: 18, badge: badge)
            btn.contentTintColor = tint
            btn.toolTip = "backbot — " + (running ? "backing up…" : st.when)
        }

        // A rotating arc is what reads as "busy" at menu bar size; the arrowhead
        // shape alone is a couple of pixels and says nothing.
        if running && spinner == nil {
            spinner = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                guard let self, let btn = self.statusItem.button else { return }
                self.spinPhase += 1.0 / 12
                if self.spinPhase > 1 { self.spinPhase -= 1 }
                btn.image = BackbotMark.statusImage(pointSize: 18,
                                                    badge: .running(phase: self.spinPhase))
            }
        } else if !running {
            spinner?.invalidate(); spinner = nil
        }

        // Menu shows only the last backup time — nothing else.
        let menu = NSMenu()
        let title: String
        switch st.status {
        case "ok", "warnings": title = "Last backup: \(st.when)"
        case "failed":         title = "Last backup FAILED: \(st.when)"
        case "partial":        title = "Last run incomplete: \(st.when)"
        default:               title = "No backups yet"
        }
        let head = NSMenuItem(title: running ? "Backing up now…" : title, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        statusItem.menu = menu
    }

    func add(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    // ── Actions ──────────────────────────────────────────────────────────
    @objc func backupNow() {
        backupRunning = true; refresh()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "\"\(BACKBOT)\" backup"]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.backupRunning = false; self?.refresh() }
        }
        try? p.run()
    }
    @objc func showStatus() {
        runOsa("tell application \"Terminal\"\nactivate\ndo script \"'\(BACKBOT)' status\"\nend tell")
    }
    @objc func openLog() { if let l = latestLog() { NSWorkspace.shared.open(l) } }
    @objc func openLogsFolder() { NSWorkspace.shared.open(LOG_DIR) }
    @objc func openSite() { NSWorkspace.shared.open(URL(string: "https://backbot.viraat.dev")!) }
    @objc func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/viraatdas/backbot")!) }
    @objc func quit() { NSApplication.shared.terminate(nil) }

    func runOsa(_ s: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", s]
        try? p.run()
    }
}

@main
struct BackbotBarApp {
    static func main() {
        // Headless flags, so install.sh / uninstall.sh can manage the login
        // item without needing to drive System Settings.
        let args = CommandLine.arguments
        if args.contains("--register-login-item") {
            do { try LoginItem.register(); print("login item registered") }
            catch { print("login item registration failed: \(error.localizedDescription)"); exit(1) }
            exit(0)
        }
        if args.contains("--unregister-login-item") {
            do { try LoginItem.unregister(); print("login item removed") }
            catch { print("login item removal failed: \(error.localizedDescription)"); exit(1) }
            exit(0)
        }

        // Single-instance guard: if another copy is already running (e.g. left
        // over from the old launchd agent), exit immediately so only one menu
        // bar icon exists.
        let me = NSRunningApplication.current
        let bundleID = me.bundleIdentifier ?? "dev.viraat.backbot.menubar"
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier }
        if !duplicates.isEmpty { exit(0) }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // no Dock icon; menu bar only
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
