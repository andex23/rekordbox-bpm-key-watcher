import AppKit
import ApplicationServices
import CoreGraphics
import os

@MainActor
final class MenuApp: NSObject, NSApplicationDelegate {
    private let watcher = Watcher()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let logger = Logger(subsystem: "com.andrewjunior.rekordbox-bpm-key-watcher", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Launched; Accessibility=\(AXIsProcessTrusted()), ScreenCapture=\(CGPreflightScreenCaptureAccess())")
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " BPM"
        watcher.onChange = { [weak self] in self?.updateMenu() }
        updateMenu()
        if CommandLine.arguments.contains("--scan-open-playlist") {
            Task { @MainActor in self.startScan() }
        }
    }

    private var hasPermissions: Bool {
        AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
    }

    private func startScan() {
        logger.info("Scan requested; Accessibility=\(AXIsProcessTrusted()), ScreenCapture=\(CGPreflightScreenCaptureAccess())")
        if hasPermissions { Task { await watcher.scan() } }
        else { updateMenu() }
    }

    private func updateMenu() {
        let counts = watcher.counts
        let verified = counts.analyzed + counts.skipped
        let complete = counts.total > 0 && verified == counts.total && counts.errors == 0
        statusItem.button?.title = watcher.scanning ? " BPM ⋯" : (complete ? " BPM ✓" : (counts.errors > 0 || counts.total > 0 ? " BPM !" : " BPM"))
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
        let scan = NSMenuItem(title: "Analyze open playlist while away", action: #selector(scanNow), keyEquivalent: "r")
        scan.target = self
        scan.isEnabled = !watcher.scanning && hasPermissions
        menu.addItem(scan)
        if watcher.scanning {
            let stop = NSMenuItem(title: "Stop analysis", action: #selector(stopScan), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
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
