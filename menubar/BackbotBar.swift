// BackbotBar — a tiny native menu bar app for backbot.
// Shows last-backup status and quick actions. No dependencies; pure Cocoa.
// Build: see build.sh (compiles into BackbotBar.app, an LSUIElement agent).

import Cocoa

let HOME = FileManager.default.homeDirectoryForCurrentUser
let LOG_DIR = HOME.appendingPathComponent(".local/share/backbot/logs")
let BACKBOT = HOME.appendingPathComponent(".local/bin/backbot").path

struct BackupState { var status: String; var when: String; var snap: String }

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var backupRunning = false

    func applicationDidFinishLaunching(_ note: Notification) {
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

        // Thin outline symbols rendered as a template image: the icon adapts to the
        // menu bar appearance (light/thin black in Light mode, white in Dark mode).
        // No color tint except red for an actual failure, so it stays clean and light.
        var symbol = "externaldrive"
        var tint: NSColor? = nil
        if running { symbol = "arrow.triangle.2.circlepath" }
        else if st.status == "failed" { symbol = "externaldrive.badge.xmark"; tint = .systemRed }
        else if st.status == "ok" || st.status == "warnings" { symbol = "externaldrive.badge.checkmark" }

        if let btn = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .light)
            let img = (NSImage(systemSymbolName: symbol, accessibilityDescription: "backbot")
                ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "backbot"))?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = true
            btn.image = img
            btn.contentTintColor = tint
            btn.toolTip = "backbot — " + (running ? "backing up…" : st.when)
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

// Single-instance guard: if another copy is already running (e.g. started by a
// second autostart mechanism), exit immediately so only one menu bar icon exists.
let me = NSRunningApplication.current
let bundleID = me.bundleIdentifier ?? "dev.viraat.backbot.menubar"
let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != me.processIdentifier }
if !duplicates.isEmpty {
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; menu bar only
let delegate = AppDelegate()
app.delegate = delegate
app.run()
