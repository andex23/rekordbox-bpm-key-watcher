import AppKit
import ApplicationServices

struct AnalysisPreferences: Codable {
    let bpm: Bool
    let key: Bool
    let phrase: Bool
    let vocal: Bool
    let auto: Bool
    let cue: Bool
}

final class RekordboxControl {
    private let bundleIdentifier = "com.pioneerdj.rekordboxdj"
    private var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }
    private var root: AXUIElement? {
        guard let app else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    var isRunning: Bool { app != nil }
    var isActive: Bool { app?.isActive == true }

    func activate() throws {
        guard let app else { throw WatcherError.noRekordbox }
        app.activate()
    }

    private func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
        return result
    }

    private func text(_ element: AXUIElement, _ attribute: CFString) -> String? {
        value(element, attribute) as? String
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private func find(_ element: AXUIElement, depth: Int = 0, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth < 12 else { return nil }
        for child in children(element) {
            if let found = find(child, depth: depth + 1, where: matches) { return found }
        }
        return nil
    }

    private func named(_ name: String, in element: AXUIElement) -> AXUIElement? {
        find(element) { [self] candidate in
            text(candidate, kAXTitleAttribute as CFString) == name ||
            text(candidate, kAXDescriptionAttribute as CFString) == name
        }
    }

    private func press(_ element: AXUIElement, label: String) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw WatcherError.actionUnavailable(label)
        }
    }

    private func preferencesWindow() -> AXUIElement? {
        guard let root else { return nil }
        return find(root) { [self] element in
            text(element, kAXTitleAttribute as CFString) == "Preferences" &&
            (text(element, kAXRoleAttribute as CFString) == kAXWindowRole as String ||
             text(element, kAXRoleAttribute as CFString) == "AXDialog")
        }
    }

    private func openPreferences() throws -> AXUIElement {
        guard isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        if let current = preferencesWindow() { return current }
        guard let root,
              let button = find(root, where: { [self] in (text($0, kAXHelpAttribute as CFString) ?? "").contains("Preferences") }) else {
            throw WatcherError.missingLayout("Preferences button")
        }
        try press(button, label: "Preferences")
        Thread.sleep(forTimeInterval: 0.25)
        guard let window = preferencesWindow() else { throw WatcherError.missingLayout("Preferences dialog") }
        return window
    }

    private func go(_ name: String, in window: AXUIElement) throws {
        guard let button = named(name, in: window) else { throw WatcherError.missingLayout(name) }
        try press(button, label: name)
        Thread.sleep(forTimeInterval: 0.08)
    }

    private func toggle(_ name: String, in window: AXUIElement) throws -> Bool {
        guard let element = named(name, in: window), let raw = value(element, kAXValueAttribute as CFString) else {
            throw WatcherError.missingLayout(name)
        }
        if let number = raw as? NSNumber { return number.boolValue }
        let string = String(describing: raw).lowercased()
        return string == "on" || string == "1" || string == "true"
    }

    private func setToggle(_ name: String, to desired: Bool, in window: AXUIElement) throws {
        if try toggle(name, in: window) != desired {
            guard let element = named(name, in: window) else { throw WatcherError.missingLayout(name) }
            try press(element, label: name)
            Thread.sleep(forTimeInterval: 0.12)
            guard try toggle(name, in: window) == desired else { throw WatcherError.verificationFailed(name) }
        }
    }

    private func closePreferences(_ window: AXUIElement) throws {
        if let close = value(window, kAXCloseButtonAttribute as CFString) {
            try press(close as! AXUIElement, label: "close Preferences")
        } else if let close = named("close", in: window) {
            try press(close, label: "close Preferences")
        } else {
            throw WatcherError.missingLayout("Preferences close button")
        }
    }

    func readPreferences() throws -> AnalysisPreferences {
        let window = try openPreferences()
        defer { try? closePreferences(window) }
        try go("Analysis", in: window)
        try go("Track Analysis", in: window)
        let bpm = try toggle("BPM / Grid", in: window)
        let key = try toggle("KEY", in: window)
        let phrase = try toggle("Phrase", in: window)
        let vocal = try toggle("Vocal", in: window)
        let auto = try !toggle("Disable", in: window)
        try go("CUE Analysis", in: window)
        let cue = try toggle("Set CUE during analysis", in: window)
        return AnalysisPreferences(bpm: bpm, key: key, phrase: phrase, vocal: vocal, auto: auto, cue: cue)
    }

    func configureAnalysis(_ missing: MissingFields) throws {
        let window = try openPreferences()
        defer { try? closePreferences(window) }
        try go("Analysis", in: window)
        try go("Track Analysis", in: window)
        try setToggle("BPM / Grid", to: missing.bpm, in: window)
        try setToggle("KEY", to: missing.key, in: window)
        try setToggle("Phrase", to: false, in: window)
        try setToggle("Vocal", to: false, in: window)
        try go("CUE Analysis", in: window)
        try setToggle("Set CUE during analysis", to: false, in: window)
    }

    func restore(_ saved: AnalysisPreferences) throws {
        let window = try openPreferences()
        defer { try? closePreferences(window) }
        try go("Analysis", in: window)
        try go("Track Analysis", in: window)
        try setToggle("BPM / Grid", to: saved.bpm, in: window)
        try setToggle("KEY", to: saved.key, in: window)
        try setToggle("Phrase", to: saved.phrase, in: window)
        try setToggle("Vocal", to: saved.vocal, in: window)
        try setToggle("Disable", to: !saved.auto, in: window)
        try go("CUE Analysis", in: window)
        try setToggle("Set CUE during analysis", to: saved.cue, in: window)
    }

    func click(windowFrame: CGRect, local: CGPoint) throws {
        guard isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        let point = CGPoint(x: windowFrame.minX + local.x, y: windowFrame.minY + local.y)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw WatcherError.actionUnavailable("mouse click")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func selectAllTracks() throws {
        guard isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw WatcherError.actionUnavailable("Select All")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    var selectedTrackCount: Int? {
        guard let root,
              let element = find(root, where: { [self] in
                  (text($0, kAXValueAttribute as CFString) ?? "").hasPrefix("Selected: ")
              }),
              let label = text(element, kAXValueAttribute as CFString),
              let match = label.range(of: "(?<=Selected: )[0-9]+(?= Tracks?)", options: .regularExpression) else { return nil }
        return Int(label[match])
    }

    func scroll(windowFrame: CGRect, local: CGPoint, lines: Int32) throws {
        guard isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        let point = CGPoint(x: windowFrame.minX + local.x, y: windowFrame.minY + local.y)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else {
            throw WatcherError.actionUnavailable("scroll")
        }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    func trackMenuAction(_ action: String) throws {
        guard isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        guard let root, let menuBarRaw = value(root, kAXMenuBarAttribute as CFString) else {
            throw WatcherError.missingLayout("Track menu")
        }
        let menuBar = menuBarRaw as! AXUIElement
        guard let trackMenu = named("Track", in: menuBar) else { throw WatcherError.missingLayout("Track menu") }
        try press(trackMenu, label: "Track menu")
        Thread.sleep(forTimeInterval: 0.08)
        guard let item = named(action, in: trackMenu) else { throw WatcherError.missingLayout(action) }
        let enabled = (value(item, kAXEnabledAttribute as CFString) as? NSNumber)?.boolValue ?? false
        guard enabled else {
            _ = AXUIElementPerformAction(trackMenu, kAXCancelAction as CFString)
            throw WatcherError.actionUnavailable(action)
        }
        try press(item, label: action)
    }

    func appleMusicAccountMismatchVisible() -> Bool {
        guard let root else { return false }
        return find(root) { [self] element in
            let label = text(element, kAXValueAttribute as CFString) ?? text(element, kAXTitleAttribute as CFString) ?? ""
            return label.localizedCaseInsensitiveContains("different Apple Music account")
        } != nil
    }

    func analysisBusy() -> Bool {
        guard let root else { return false }
        return find(root) { [self] element in
            let label = text(element, kAXValueAttribute as CFString) ?? text(element, kAXTitleAttribute as CFString) ?? ""
            return label.contains("Analyzing:") || label.contains("Importing ")
        } != nil
    }

    func confirmAnalysisIfNeeded() throws {
        guard let root else { throw WatcherError.noRekordbox }
        func analysisButton() -> AXUIElement? {
            var windows: [AXUIElement] = []
            if let focused = value(root, kAXFocusedWindowAttribute as CFString) {
                windows.append(focused as! AXUIElement)
            }
            windows += value(root, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
            for window in windows {
                let isAnalysis = find(window) { [self] element in
                    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                        .contains { (text(element, $0 as CFString) ?? "").contains("Analysis Setting") }
                } != nil
                if isAnalysis, let button = named("OK", in: window) { return button }
            }
            return nil
        }
        // The dialog can appear after the Track menu action returns. Its OK
        // button is in a separate focused window, not the main window tree.
        for _ in 0..<10 {
            guard let button = analysisButton() else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            if AXUIElementPerformAction(button, kAXPressAction as CFString) != .success {
                try clickCenter(of: button)
            }
            Thread.sleep(forTimeInterval: 0.2)
            if analysisButton() != nil { try clickCenter(of: button) }
            if analysisButton() == nil { return }
        }
        if analysisButton() != nil { throw WatcherError.actionUnavailable("analysis confirmation") }
    }

    private func clickCenter(of element: AXUIElement) throws {
        guard let positionRaw = value(element, kAXPositionAttribute as CFString),
              let sizeRaw = value(element, kAXSizeAttribute as CFString) else {
            throw WatcherError.missingLayout("analysis OK button position")
        }
        let position = positionRaw as! AXValue
        let size = sizeRaw as! AXValue
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else {
            throw WatcherError.missingLayout("analysis OK button bounds")
        }
        let point = CGPoint(x: origin.x + dimensions.width / 2, y: origin.y + dimensions.height / 2)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw WatcherError.actionUnavailable("analysis OK button")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
