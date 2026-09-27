import AppKit

@MainActor
final class FloatingWidget: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "BPM & Key")
    private let subtitle = NSTextField(labelWithString: "Ready")
    private let progress = AeroProgress()
    private let run = AeroButton(title: "Start analysis", target: nil, action: nil)
    private let watcher: Watcher
    private var timer: Timer?
    var onRun: (() -> Void)?
    var onDetails: (() -> Void)?
    var enabled = true

    init(watcher: Watcher) {
        self.watcher = watcher
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 125),
                        styleMask: [.titled, .closable, .miniaturizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        AeroTheme.apply(to: panel)
        panel.title = "BPM & Key"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        // Utility panels do not reliably miniaturize as ordinary Dock windows.
        // Keep these controls usable without activating the menu-bar app.
        for (kind, action) in [(NSWindow.ButtonType.closeButton, #selector(closeWidget)),
                               (.miniaturizeButton, #selector(minimizeWidget))] {
            let button = panel.standardWindowButton(kind)
            button?.isEnabled = true
            button?.target = self
            button?.action = action
        }
        title.textColor = .black; subtitle.textColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.frame = NSRect(x: 12, y: 10, width: 286, height: 108)
        stack.autoresizingMask = [.width, .height]
        title.font = AeroTheme.font(13, bold: true)
        subtitle.font = AeroTheme.font(11)
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.widthAnchor.constraint(equalToConstant: 286).isActive = true
        progress.isIndeterminate = false; progress.style = .bar
        progress.widthAnchor.constraint(equalToConstant: 286).isActive = true
        run.target = self; run.action = #selector(toggleRun); run.bezelStyle = .rounded
        let details = AeroButton(title: "Details…", target: self, action: #selector(details)); details.bezelStyle = .rounded
        let buttons = NSStackView(views: [run, details])
        for view in [title, subtitle, progress, buttons] { stack.addArrangedSubview(view) }
        panel.contentView?.addSubview(stack)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        guard enabled,
              let rb = NSRunningApplication.runningApplications(withBundleIdentifier: "com.pioneerdj.rekordboxdj").first,
              rb.isActive || NSApp.isActive,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == rb.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 && (($0[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0) > 600 }),
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { panel.orderOut(nil); return }
        if panel.isMiniaturized { return }
        if !panel.isVisible {
            let desktopHeight = NSScreen.screens.first?.frame.height ?? 900
            panel.setFrameTopLeftPoint(NSPoint(x: (bounds["X"] ?? 0) + (bounds["Width"] ?? 900) - 330,
                                               y: desktopHeight - (bounds["Y"] ?? 0) - 70))
            panel.orderFrontRegardless()
        }
        let verified = watcher.counts.analyzed + watcher.counts.skipped
        title.stringValue = (watcher.scanning || watcher.libraryRunning) ? "\(verified)/\(watcher.counts.total) verified" : "BPM & Key · \(watcher.paused ? "Paused" : "Ready")"
        subtitle.stringValue = watcher.displayStatus
        subtitle.toolTip = watcher.displayStatus
        progress.maxValue = Double(max(1, watcher.counts.total)); progress.doubleValue = Double(verified)
        run.title = (watcher.scanning || watcher.libraryRunning) ? "Pause" : (watcher.session == nil ? "Start analysis" : "Resume")
    }
    func show() {
        enabled = true
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        refresh()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWidget()
        return false
    }
    @objc private func minimizeWidget() { enabled = false; panel.orderOut(nil) }
    @objc private func closeWidget() {
        watcher.pauseForUser()
        minimizeWidget()
    }
    @objc private func toggleRun() { if watcher.scanning || watcher.libraryRunning { watcher.pauseForUser() } else { onRun?() } }
    @objc private func details() { onDetails?() }
}
