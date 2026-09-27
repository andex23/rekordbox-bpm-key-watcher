import AppKit
import ApplicationServices
import CoreGraphics
import os

@MainActor
final class MenuApp: NSObject, NSApplicationDelegate {
    private let watcher = Watcher()
    private var progress: ProgressWindow!
    private var widget: FloatingWidget!
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let logger = Logger(subsystem: "com.andrewjunior.rekordbox-bpm-key-watcher", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Launched; Accessibility=\(AXIsProcessTrusted()), ScreenCapture=\(CGPreflightScreenCaptureAccess())")
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " BPM"
        progress = ProgressWindow(watcher: watcher)
        widget = FloatingWidget(watcher: watcher)
        widget.onRun = { [weak self] in guard let self else { return }; self.startScan() }
        widget.onDetails = { [weak self] in self?.progress.present() }
        progress.onPermissions = { [weak self] in self?.grantPermissions() }
        progress.onAll = { [weak self] in self?.startLibrary() }
        progress.onStart = { [weak self] resume, retryIDs, preflight in
            self?.startScan(resume: resume, retryIDs: retryIDs, preflight: preflight)
        }
        watcher.onChange = { [weak self] in self?.updateMenu() }
        updateMenu()
        if CommandLine.arguments.contains("--scan-open-playlist") {
            Task { @MainActor in
                if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--verify-track=") }) {
                    guard let number = Int(arg.dropFirst("--verify-track=".count)),
                          let track = self.watcher.session?.tracks.first(where: { $0.number == number }) else { return }
                    self.startScan(resume: true, retryIDs: [track.id])
                } else {
                    self.startScan()
                }
            }
        }
    }

    private var hasPermissions: Bool {
        AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
    }

    private func startScan(resume: Bool = false, retryIDs: Set<String>? = nil, preflight: Bool = false) {
        guard !watcher.libraryRunning else { return }
        logger.info("Scan requested; Accessibility=\(AXIsProcessTrusted()), ScreenCapture=\(CGPreflightScreenCaptureAccess())")
        if !hasPermissions { progress.present() }
        if hasPermissions {
            progress.hideForScan()
            Task { await watcher.scan(resume: resume, retryOnly: retryIDs, preflightOnly: preflight) }
        }
        else { updateMenu() }
    }

    private func updateMenu() {
        progress?.refresh()
        widget?.refresh()
        let counts = watcher.counts
        let verified = counts.analyzed + counts.skipped
        let libraryOK = watcher.libraryQueue.map { $0.discoveryErrors.isEmpty && !$0.jobs.isEmpty && $0.jobs.allSatisfy { $0.state == "Complete" } } ?? true
        let complete = !watcher.libraryRunning && libraryOK && counts.total > 0 && verified == counts.total && counts.errors == 0
        statusItem.button?.title = (watcher.scanning || watcher.libraryRunning) ? " BPM ⋯" : (complete ? " BPM ✓" : (counts.errors > 0 || counts.total > 0 ? " BPM !" : " BPM"))
        let menu = NSMenu()
        let headline: String
        if !AXIsProcessTrusted() {
            headline = "Grant Accessibility in System Settings"
        } else if !CGPreflightScreenCaptureAccess() {
            headline = "Grant Screen Recording in System Settings"
        } else {
            headline = watcher.status
        }
        let status = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let countItem = NSMenuItem(title: "\(verified)/\(counts.total) verified · \(counts.analyzed) analyzed · \(counts.skipped) already filled · \(counts.errors) errors", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())
        let floating = NSMenuItem(title: "Show floating widget", action: #selector(toggleWidget), keyEquivalent: "")
        floating.target = self
        floating.state = widget.enabled ? .on : .off
        menu.addItem(floating)
        let show = NSMenuItem(title: "Show playlist progress…", action: #selector(showProgress), keyEquivalent: "p")
        show.target = self
        menu.addItem(show)
        if watcher.session != nil {
            let resume = NSMenuItem(title: "Resume saved playlist", action: #selector(resumeScan), keyEquivalent: "")
            resume.target = self
            resume.isEnabled = !watcher.scanning && !watcher.libraryRunning && hasPermissions
            menu.addItem(resume)
        }
        let scan = NSMenuItem(title: "Start analysis of open playlist", action: #selector(scanNow), keyEquivalent: "r")
        scan.target = self
        scan.isEnabled = !watcher.scanning && !watcher.libraryRunning && hasPermissions
        menu.addItem(scan)
        let all = NSMenuItem(title: "Analyze all Apple Music playlists", action: #selector(analyzeLibrary), keyEquivalent: "")
        all.target = self
        all.isEnabled = !watcher.scanning && !watcher.libraryRunning && hasPermissions
        menu.addItem(all)
        let resumeAll = NSMenuItem(title: "Resume saved library session", action: #selector(resumeLibrary), keyEquivalent: "")
        resumeAll.target = self
        resumeAll.isEnabled = all.isEnabled && watcher.libraryQueue != nil
        menu.addItem(resumeAll)
        if watcher.scanning || watcher.libraryRunning {
            let stop = NSMenuItem(title: "Pause analysis", action: #selector(stopScan), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
        let restore = NSMenuItem(title: "Restore previous analysis settings", action: #selector(restoreSettings), keyEquivalent: "")
        restore.target = self
        restore.isEnabled = !watcher.scanning && !watcher.libraryRunning && hasPermissions
        menu.addItem(restore)
        let permissions = NSMenuItem(title: "Grant permissions…", action: #selector(grantPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        if !watcher.recent.isEmpty {
            menu.addItem(.separator())
            for line in watcher.recent.prefix(8) {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func startLibrary(resume: Bool = false) {
        guard hasPermissions else { progress.present(); return }
        progress.hideForScan()
        Task { await watcher.scanLibrary(resume: resume) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        widget.show()
        return true
    }
    @objc private func analyzeLibrary() { startLibrary() }
    @objc private func resumeLibrary() { startLibrary(resume: true) }
    @objc private func toggleWidget() { widget.show(); updateMenu() }
    @objc private func restoreSettings() { Task { await watcher.restoreSettings() } }
    @objc private func showProgress() { progress.present() }
    @objc private func resumeScan() { startScan(resume: true) }
    @objc private func scanNow() { startScan() }
    @objc private func stopScan() { watcher.stop() }
    @objc private func grantPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestScreenCaptureAccess()
        updateMenu()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private static func menuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let platter = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14))
            platter.lineWidth = 1.8
            platter.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.3, y: 7.3, width: 3.4, height: 3.4)).fill()
            let beat = NSBezierPath()
            beat.move(to: NSPoint(x: 13.8, y: 12.8))
            beat.line(to: NSPoint(x: 15.9, y: 12.8))
            beat.line(to: NSPoint(x: 16.5, y: 14.4))
            beat.lineWidth = 1.8
            beat.lineCapStyle = .round
            beat.lineJoinStyle = .round
            beat.stroke()
            return true
        }
        icon.isTemplate = true
        return icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.shutdown()
    }
}

@main
struct RekordboxBPMKeyWatcher {
    static func main() {
        let application = NSApplication.shared
        let delegate = MenuApp()
        application.delegate = delegate
        application.run()
    }
}
