import AppKit

@MainActor
final class ProgressWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let watcher: Watcher
    private let headline = NSTextField(labelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let table = NSTableView()
    private let libraryPicker = NSPopUpButton()
    private var reportWindow: NSWindow?
    private let bar = AeroProgress()
    private var rows: [TrackProgress] = []
    var onPermissions: (() -> Void)?
    var onAll: (() -> Void)?
    var onStart: ((Bool, Set<String>?, Bool) -> Void)?

    init(watcher: Watcher) {
        self.watcher = watcher
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        AeroTheme.apply(to: panel)
        panel.title = "Rekordbox BPM & Key — Playlist progress"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.center()
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            content.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        headline.font = AeroTheme.font(19, bold: true)
        content.addArrangedSubview(headline)
        content.addArrangedSubview(summary)
        bar.isIndeterminate = false
        bar.style = .bar
        content.addArrangedSubview(bar)
        let buttons = NSStackView()
        for (title, action) in [("Check playlist", #selector(preflight)), ("Analyze / Resume", #selector(resume)),
                                ("Pause", #selector(pause)), ("Retry failed", #selector(retryFailed)),
                                ("Retry selected", #selector(retrySelected)), ("Permissions…", #selector(permissions))] {
            let button = AeroButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            buttons.addArrangedSubview(button)
        }
        content.addArrangedSubview(buttons)
        let orderButtons = NSStackView()
        for (title, action) in [("Analyze all Apple Music playlists", #selector(allPlaylists))] {
            let button = AeroButton(title: title, target: self, action: action); button.bezelStyle = .rounded
            orderButtons.addArrangedSubview(button)
        }
        content.addArrangedSubview(orderButtons)
        libraryPicker.target = self; libraryPicker.action = #selector(pickPlaylist)
        content.addArrangedSubview(libraryPicker)
        let libraryReport = AeroButton(title: "Library progress / skipped playlists…", target: self, action: #selector(libraryReport))
        libraryReport.bezelStyle = .rounded
        content.addArrangedSubview(libraryReport)
        for (id, title, width) in [("number", "#", 35.0), ("title", "Track", 190.0), ("artist", "Artist", 130.0),
                                   ("phase", "Status", 85.0), ("bpm", "BPM", 65.0), ("key", "Key", 55.0), ("detail", "Details / next step", 310.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 28
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        content.addArrangedSubview(scroll)
        let footer = NSTextField(wrappingLabelWithString: "Keep Rekordbox visible and the Mac unlocked. Keyboard or mouse activity pauses automation. Saved results are rechecked on resume. Stream access and analysis locks may only become known when a track is selected.")
        footer.font = AeroTheme.font(11)
        footer.textColor = NSColor(calibratedWhite: 0.2, alpha: 1)
        content.addArrangedSubview(footer)
        for view in [headline, summary, bar, scroll, footer] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        if watcher.scanning || watcher.libraryRunning { watcher.pauseForUser() }
        window?.orderFrontRegardless()
        refresh()
    }
    func hideForScan() {
        window?.orderOut(nil)
        reportWindow?.orderOut(nil)
    }
    func refresh() {
        let selected = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        let picked = libraryPicker.indexOfSelectedItem
        libraryPicker.removeAllItems()
        libraryPicker.addItem(withTitle: "Saved playlist results…")
        for job in watcher.libraryQueue?.jobs ?? [] { libraryPicker.addItem(withTitle: "\(job.name) — \(job.state)") }
        if picked >= 0 && picked < libraryPicker.numberOfItems { libraryPicker.selectItem(at: picked) }
        rows = watcher.session?.tracks ?? []

        headline.stringValue = watcher.session?.playlist ?? "Open an Apple Music playlist in Rekordbox"
        let verified = watcher.counts.analyzed + watcher.counts.skipped
        let date = watcher.session.map { DateFormatter.localizedString(from: $0.updatedAt, dateStyle: .short, timeStyle: .short) } ?? "—"
        summary.stringValue = "\(watcher.displayStatus)\nThis run: \(verified)/\(watcher.counts.total) verified · \(watcher.counts.errors) errors · Last saved: \(date)"
        bar.maxValue = Double(max(1, watcher.counts.total))
        bar.doubleValue = Double(verified)
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { selected.contains(rows[$0].id) }), byExtendingSelection: false)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let track = rows[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "number": value = String(track.number)
        case "title": value = track.title
        case "artist": value = track.artist
        case "phase": value = track.phase.rawValue
        case "bpm": value = track.bpm
        case "key": value = track.key == "?" ? "Present" : track.key
        default: value = track.detail
        }
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = value
        if track.phase == .failed { label.textColor = .systemRed }
        return label
    }
    @objc private func permissions() { onPermissions?() }
    @objc private func pickPlaylist() { watcher.useSavedPlaylist(at: libraryPicker.indexOfSelectedItem - 1) }
    @objc private func libraryReport() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 450), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Apple Music library progress"; panel.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.autoresizingMask = [.width]
        text.font = .systemFont(ofSize: 13)
        var lines = watcher.libraryQueue?.jobs.map { "\($0.state): \($0.name)\($0.error.isEmpty ? "" : " — " + $0.error)" } ?? ["No library scan yet."]
        lines += watcher.libraryQueue?.discoveryErrors ?? []
        text.string = lines.joined(separator: "\n\n")
        scroll.documentView = text; panel.contentView?.addSubview(scroll)
        reportWindow = panel; panel.center(); panel.orderFrontRegardless()
    }
    @objc private func allPlaylists() { onAll?() }
    @objc private func preflight() { onStart?(false, nil, true) }
    @objc private func resume() { onStart?(watcher.session != nil, nil, false) }
    @objc private func pause() { watcher.pauseForUser() }
    @objc private func retryFailed() {
        let ids = Set(rows.filter { $0.phase == .failed }.map(\.id))
        if !ids.isEmpty { onStart?(true, ids, false) }
    }
    @objc private func retrySelected() {
        let ids = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        if !ids.isEmpty { onStart?(true, ids, false) }
    }
}
