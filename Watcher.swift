import AppKit
import CoreGraphics
import os

struct ScanCounts {
    var playlists = 0
    var analyzed = 0
    var skipped = 0
    var errors = 0
}

@MainActor
final class Watcher {
    private let reader = WindowReader()
    private let control = RekordboxControl()
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.andrewjunior.rekordbox-bpm-key-watcher", category: "watcher")
    private let recoveryKey = "SavedAnalysisPreferences"
    private(set) var paused = false
    private(set) var scanning = false
    private(set) var counts = ScanCounts()
    private(set) var status = "Ready for an away session"
    private(set) var recent: [String] = []
    var onChange: (() -> Void)?

    func stop() {
        guard scanning else { return }
        paused = true
        note("Stopping after the current Rekordbox action")
    }

    private func note(_ message: String) {
        logger.info("\(message, privacy: .public)")
        recent.insert("\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))  \(message)", at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
        status = message
        onChange?()
    }

    func shutdown() { try? restorePendingIfNeeded() }

    private func snapshot() async throws -> (CapturedWindow, [Word]) {
        for attempt in 0..<3 {
            do {
                let captured = try await reader.capture()
                let words = try reader.recognize(captured)
                let playlistFound = activePlaylistName(words, size: captured.frame.size) != nil
                let tableFound = (try? TableLayout.detect(words, size: captured.frame.size)) != nil
                if (!playlistFound || !tableFound) && attempt < 2 {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                if !playlistFound || !tableFound {
                    let clues = words.filter {
                        $0.text.localizedCaseInsensitiveContains("track") || $0.text.localizedCaseInsensitiveContains("bpm") ||
                        $0.text.localizedCaseInsensitiveContains("key") || $0.text.localizedCaseInsensitiveContains("preview")
                    }.prefix(20).map { "\($0.text)@\(Int($0.x)),\(Int($0.y))" }.joined(separator: "; ")
                    logger.info("OCR layout: playlist \(playlistFound), table \(tableFound), \(words.count) words, frame \(Int(captured.frame.width))x\(Int(captured.frame.height)), clues \(clues, privacy: .public)")
                }
                return (captured, words)
            } catch {
                if attempt == 2 { throw error }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw WatcherError.windowHidden
    }

    private func activePlaylistName(_ words: [Word], size: CGSize) -> String? {
        let titles = words.filter {
            PlaylistList.name(fromHeading: $0.text) != nil &&
            $0.y > size.height * 0.45 && $0.y < size.height * 0.78 &&
            $0.rect.minX > size.width * 0.17
        }
        guard let title = titles.min(by: { abs($0.y - size.height * 0.65) < abs($1.y - size.height * 0.65) }) else { return nil }
        return PlaylistList.name(fromHeading: title.text)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func sameTitle(_ first: String, _ second: String) -> Bool {
        let a = normalized(first), b = normalized(second)
        if a == b || (min(a.count, b.count) >= 6 && (a.hasPrefix(b) || b.hasPrefix(a))) { return true }
        guard min(a.count, b.count) >= 6, a.prefix(3) == b.prefix(3) else { return false }
        let left = Array(a), right = Array(b)
        var previous = Array(0...right.count)
        for (index, character) in left.enumerated() {
            var current = [index + 1] + Array(repeating: 0, count: right.count)
            for column in right.indices {
                current[column + 1] = min(previous[column + 1] + 1,
                                          current[column] + 1,
                                          previous[column] + (character == right[column] ? 0 : 1))
            }
            previous = current
        }
        return previous[right.count] <= max(2, min(left.count, right.count) / 5)
    }

    private func matchingRow(_ row: TrackRow, layout: TableLayout, words: [Word]) -> TrackRow? {
        if let numbered = layout.rows(words).first(where: { $0.number == row.number && sameTitle($0.title, row.title) }) {
            return numbered
        }
        // During Apple Music import, OCR can lose the tiny track number while
        // the larger title remains readable. Recover only a matching title.
        let titles = words.filter {
            $0.y > layout.headerY + 8 && $0.y < layout.bottomY - 6 &&
            $0.x >= layout.titleX && $0.x < layout.artistX
        }
        for word in titles where sameTitle(word.text, row.title) {
            let recovered = layout.row(number: row.number, y: word.y, words: words)
            if sameTitle(recovered.title, row.title) { return recovered }
        }
        return nil
    }

    private func requireOpenPlaylist(_ name: String, words: [Word], size: CGSize) throws {
        guard let active = activePlaylistName(words, size: size), normalized(active) == normalized(name) else {
            throw WatcherError.verificationFailed("the open playlist is still \(name)")
        }
    }

    private func leadingNumbers(_ words: [Word], playlist: String) -> [Int] {
        let count = words.compactMap { word -> Int? in
            guard PlaylistList.name(fromHeading: word.text).map({ normalized($0) == normalized(playlist) }) == true else { return nil }
            return PlaylistList.count(fromHeading: word.text)
        }.first
        return Array(1...max(1, min(3, count ?? 3)))
    }

    private func hasLeadingRows(_ words: [Word], layout: TableLayout, playlist: String) -> Bool {
        let numbers = Set(layout.rows(words).map(\.number))
        return leadingNumbers(words, playlist: playlist).allSatisfy(numbers.contains)
    }

    func scan() async {
        guard !scanning else { return }
        guard control.isRunning else { status = "Waiting for Rekordbox"; onChange?(); return }
        paused = false
        scanning = true
        counts = ScanCounts()
        note("Checking the open playlist")
        defer { scanning = false; onChange?() }
        var openPlaylist: String?
        do {
            try control.activate()
            let (openingCapture, openingWords) = try await snapshot()
            guard let name = activePlaylistName(openingWords, size: openingCapture.frame.size) else {
                throw WatcherError.missingLayout("the currently open playlist; select an Apple Music playlist before starting")
            }
            openPlaylist = name
            counts.playlists = 1
            note("Analyzing open playlist: \(name)")
            try restorePendingIfNeeded()
            try await scanTrackTable(name)
        } catch {
            counts.errors += 1
            note(error.localizedDescription)
        }
        if openPlaylist == nil && defaults.data(forKey: recoveryKey) == nil {
            paused = false
            return
        }
        if control.isRunning {
            do {
                if defaults.data(forKey: recoveryKey) != nil {
                    try control.activate()
                    try restorePendingIfNeeded()
                }
                if let openPlaylist {
                    let (finalCapture, finalWords) = try await snapshot()
                    guard let finalName = activePlaylistName(finalWords, size: finalCapture.frame.size), normalized(finalName) == normalized(openPlaylist) else {
                        throw WatcherError.verificationFailed("the open playlist stayed on \(openPlaylist)")
                    }
                }
                note("\(paused ? "Stopped" : "Done"): \(counts.analyzed) analyzed, \(counts.skipped) skipped, \(counts.errors) errors")
            } catch {
                counts.errors += 1
                note("Finish failed: \(error.localizedDescription)")
            }
        } else {
            note("Rekordbox closed; reopen it to restore analysis settings")
        }
        paused = false
    }

    private func scanTrackTable(_ playlist: String) async throws {
        guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        var (captured, words) = try await snapshot()
        try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
        var layout = try TableLayout.detect(words, size: captured.frame.size)
        for _ in 0..<20 {
            try control.scroll(windowFrame: captured.frame,
                               local: CGPoint(x: layout.titleX + 90, y: layout.headerY + 90), lines: 7)
            try await Task.sleep(nanoseconds: 300_000_000)
            (captured, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
            layout = try TableLayout.detect(words, size: captured.frame.size)
            if hasLeadingRows(words, layout: layout, playlist: playlist) { break }
        }
        // Rekordbox keeps the user's table sort between playlists. A playlist
        // sorted by Artist or BPM does not expose row 1 at its top, so put the
        // open table in track-number order before reading or selecting it.
        if !hasLeadingRows(words, layout: layout, playlist: playlist) {
            for _ in 0..<2 {
                try control.click(windowFrame: captured.frame,
                                  local: CGPoint(x: layout.numberX, y: layout.headerY))
                try await Task.sleep(nanoseconds: 300_000_000)
                try await scrollToTop(playlist)
                (captured, words) = try await snapshot()
                try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
                layout = try TableLayout.detect(words, size: captured.frame.size)
                if hasLeadingRows(words, layout: layout, playlist: playlist) { break }
            }
            guard hasLeadingRows(words, layout: layout, playlist: playlist) else {
                throw WatcherError.verificationFailed("track-number order in \(playlist)")
            }
        }
        var rows: [TrackRow] = []
        for attempt in 0..<15 where !paused && control.isRunning {
            guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
            (captured, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
            layout = try TableLayout.detect(words, size: captured.frame.size)
            rows = layout.rows(words)
            if !rows.isEmpty { break }
            let numericWords = words.filter {
                $0.y > layout.headerY + 16 && $0.y < layout.bottomY - 6 &&
                $0.x > layout.numberX - 50 && $0.x < layout.numberX + 50
            }.prefix(4).map(\.text).joined(separator: ",")
            logger.info("\(playlist, privacy: .public): no rows (attempt \(attempt + 1), numberX \(Int(layout.numberX)), candidates \(numericWords, privacy: .public))")
            if attempt >= 2 && words.contains(where: { $0.text.range(of: "\\(0 Tracks?\\)", options: .regularExpression) != nil }) { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if rows.isEmpty { throw WatcherError.missingLayout("track rows in \(playlist)") }
        logger.info("\(playlist, privacy: .public): found \(rows.count) visible track rows")
        let expectedCount = words.compactMap { word -> Int? in
            guard PlaylistList.name(fromHeading: word.text).map({ normalized($0) == normalized(playlist) }) == true else { return nil }
            return PlaylistList.count(fromHeading: word.text)
        }.first
        var batchNumbers = Set<Int>()
        if let expectedCount, expectedCount > 1,
           let (missing, numbers) = try await uniformMissingFields(playlist: playlist, expectedCount: expectedCount) {
            note("Importing and analyzing \(numbers.count) tracks together")
            do {
                try await analyzeBatch(playlist: playlist, count: expectedCount, missing: missing)
                batchNumbers = numbers
            } catch {
                guard control.isRunning, control.isActive, !paused else { throw error }
                counts.errors += 1
                note("Batch analysis did not finish: \(error.localizedDescription). Checking tracks individually")
            }
        }
        try await scrollToTop(playlist)
        var seenRows = Set<Int>()
        var emptyScrolls = 0
        var unstableRows: [Int: Int] = [:]
        var consecutiveErrors = 0
        for pass in 0..<3 {
          if let expectedCount, seenRows.count >= expectedCount { break }
          if pass > 0 {
              note("Rechecking unreadable rows in \(playlist) (pass \(pass + 1))")
              try await scrollToTop(playlist)
              emptyScrolls = 0
          }
          for _ in 0..<500 where emptyScrolls < 5 && !paused && control.isRunning {
            guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
            (captured, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
            layout = try TableLayout.detect(words, size: captured.frame.size)
            guard let row = layout.rows(words).first(where: { !seenRows.contains($0.number) }) else {
                let before = layout.rows(words).map(\.number)
                try control.scroll(windowFrame: captured.frame,
                                   local: CGPoint(x: layout.titleX + 90, y: min(layout.bottomY - 30, layout.headerY + 100)), lines: emptyScrolls >= 2 ? -25 : -7)
                try await Task.sleep(nanoseconds: 200_000_000)
                let (scrolledCapture, scrolledWords) = try await snapshot()
                try requireOpenPlaylist(playlist, words: scrolledWords, size: scrolledCapture.frame.size)
                let scrolledLayout = try TableLayout.detect(scrolledWords, size: scrolledCapture.frame.size)
                let after = scrolledLayout.rows(scrolledWords).map(\.number)
                emptyScrolls = after == before ? emptyScrolls + 1 : 0
                logger.info("Scroll rows \(before.map(String.init).joined(separator: ","), privacy: .public) -> \(after.map(String.init).joined(separator: ","), privacy: .public); stalls \(emptyScrolls)")
                continue
            }
            emptyScrolls = 0
            var resetToTop = false
            let (liveCapture, liveWords) = try await snapshot()
            try requireOpenPlaylist(playlist, words: liveWords, size: liveCapture.frame.size)
            let liveLayout = try TableLayout.detect(liveWords, size: liveCapture.frame.size)
            if let liveRow = liveLayout.rows(liveWords).first(where: {
                $0.number == row.number &&
                (row.title.isEmpty || $0.title.isEmpty || sameTitle($0.title, row.title))
            }) {
                seenRows.insert(row.number)
                guard !liveRow.bpm.isEmpty else {
                    counts.errors += 1
                    note("\(playlist) #\(row.number): BPM unreadable; skipped")
                    continue
                }
                if !liveRow.missing.any {
                    if batchNumbers.contains(row.number) {
                        counts.analyzed += 1
                        note("Verified \(playlist) #\(row.number): BPM \(liveRow.bpm), key \(liveRow.key)")
                    } else {
                        counts.skipped += 1
                    }
                } else {
                    guard !liveRow.title.isEmpty else {
                        counts.errors += 1
                        note("\(playlist) #\(row.number): title unreadable; skipped")
                        continue
                    }
                    do {
                        let result = try await process(liveRow, playlist: playlist)
                        resetToTop = true
                        counts.analyzed += 1
                        consecutiveErrors = 0
                        note("Saved \(playlist) #\(row.number): BPM \(result.bpm), key \(result.key)")
                    } catch {
                        resetToTop = true
                        counts.errors += 1
                        note("\(playlist) #\(row.number): \(error.localizedDescription)")
                        if case WatcherError.appleMusicAccountMismatch = error {
                            consecutiveErrors = 0
                        } else {
                            consecutiveErrors += 1
                            if consecutiveErrors >= 12 { throw WatcherError.actionUnavailable("twelve consecutive track analyses") }
                        }
                    }
                }
            } else {
                unstableRows[row.number, default: 0] += 1
                if unstableRows[row.number, default: 0] >= 3 {
                    seenRows.insert(row.number)
                    counts.errors += 1
                    note("\(playlist) #\(row.number): row moved or changed; skipped")
                }
            }
            (captured, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
            layout = try TableLayout.detect(words, size: captured.frame.size)
            if resetToTop {
                try control.scroll(windowFrame: captured.frame,
                                   local: CGPoint(x: layout.titleX + 90, y: layout.headerY + 90), lines: 7)
            }
          }
        }
        if let expectedCount, seenRows.count < expectedCount, !paused {
            let unseen = (1...expectedCount).filter { !seenRows.contains($0) }
            counts.errors += unseen.count
            note("Could not verify \(unseen.count) tracks in \(playlist): \(unseen.map(String.init).joined(separator: ", "))")
        }
    }

    private func scrollToTop(_ playlist: String) async throws {
        for _ in 0..<20 {
            let (captured, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
            let layout = try TableLayout.detect(words, size: captured.frame.size)
            if hasLeadingRows(words, layout: layout, playlist: playlist) { return }
            try control.scroll(windowFrame: captured.frame,
                               local: CGPoint(x: layout.titleX + 90, y: layout.headerY + 90), lines: 7)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // Analyze the whole playlist in one Rekordbox command only when OCR has
    // identified every row and every track needs the same fields. This avoids
    // changing a completed BPM, grid, key, or cue for a mixed playlist.
    private func uniformMissingFields(playlist: String, expectedCount: Int) async throws -> (MissingFields, Set<Int>)? {
        var found: [Int: TrackRow] = [:]
        for pass in 0..<3 where found.count < expectedCount && !paused {
            if pass > 0 { try await scrollToTop(playlist) }
            var unchangedScrolls = 0
            for _ in 0..<max(20, expectedCount / 3) where unchangedScrolls < 5 && !paused {
                guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
                let (captured, words) = try await snapshot()
                try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
                let layout = try TableLayout.detect(words, size: captured.frame.size)
                let before = found.count
                for row in layout.rows(words) {
                    guard row.number <= expectedCount,
                          Double(row.bpm.replacingOccurrences(of: ",", with: ".")) != nil else { continue }
                    // One reliably completed row proves this cannot be an
                    // all-missing playlist. Keep its existing analysis intact.
                    if !row.missing.any { return nil }
                    if let previous = found[row.number],
                       (!sameTitle(previous.title, row.title) || previous.missing != row.missing) { return nil }
                    found[row.number] = row
                }
                if found.count == expectedCount { break }
                unchangedScrolls = found.count == before ? unchangedScrolls + 1 : 0
                try control.scroll(windowFrame: captured.frame,
                                   local: CGPoint(x: layout.titleX + 90, y: min(layout.bottomY - 30, layout.headerY + 100)), lines: -7)
            }
        }
        guard found.count == expectedCount,
              Set(found.keys) == Set(1...expectedCount),
              let first = found[1]?.missing, first.any,
              found.values.allSatisfy({ $0.missing == first }) else { return nil }
        return (first, Set(found.keys))
    }

    private func analyzeBatch(playlist: String, count: Int, missing: MissingFields) async throws {
        let original = try control.readPreferences()
        defaults.set(try JSONEncoder().encode(original), forKey: recoveryKey)
        defer { try? restorePendingIfNeeded() }
        try control.configureAnalysis(missing)
        try await scrollToTop(playlist)
        try await selectWholePlaylist(playlist, count: count)
        do {
            try control.trackMenuAction("Import To Collection")
        } catch WatcherError.actionUnavailable {
            // Rekordbox disables Import when the selection is already in Collection.
        }
        var importIdle = 0
        for _ in 0..<max(90, count * 12) {
            if paused { throw WatcherError.actionUnavailable("scan paused") }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            importIdle = control.analysisBusy() ? 0 : importIdle + 1
            if importIdle >= 5 { break }
        }
        try await selectWholePlaylist(playlist, count: count)
        try control.trackMenuAction("Analyze Track")
        try control.confirmAnalysisIfNeeded()
        note("Rekordbox is analyzing \(count) tracks in one batch")
        var analysisIdle = 0
        for tick in 0..<max(300, count * 90) {
            if !control.isRunning { throw WatcherError.noRekordbox }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            analysisIdle = control.analysisBusy() ? 0 : analysisIdle + 1
            if analysisIdle >= 15 && tick >= 15 { return }
        }
        throw WatcherError.verificationFailed("completion of batch analysis")
    }

    private func selectWholePlaylist(_ playlist: String, count: Int) async throws {
        let (captured, words) = try await snapshot()
        try requireOpenPlaylist(playlist, words: words, size: captured.frame.size)
        let layout = try TableLayout.detect(words, size: captured.frame.size)
        guard let first = layout.rows(words).first else { throw WatcherError.missingLayout("first track for batch selection") }
        try control.click(windowFrame: captured.frame,
                          local: CGPoint(x: layout.titleX + 60, y: first.y))
        try control.selectAllTracks()
        for _ in 0..<10 {
            if control.selectedTrackCount == count { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw WatcherError.verificationFailed("selection of all \(count) playlist tracks")
    }

    private func process(_ row: TrackRow, playlist: String) async throws -> TrackRow {
        guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
        let original = try control.readPreferences()
        defaults.set(try JSONEncoder().encode(original), forKey: recoveryKey)
        defer { try? restorePendingIfNeeded() }
        try control.configureAnalysis(row.missing)
        let (readyCapture, readyWords) = try await snapshot()
        try requireOpenPlaylist(playlist, words: readyWords, size: readyCapture.frame.size)
        let readyLayout = try TableLayout.detect(readyWords, size: readyCapture.frame.size)
        guard let readyRow = readyLayout.rows(readyWords).first(where: { $0.number == row.number && sameTitle($0.title, row.title) && $0.missing == row.missing }) else {
            throw WatcherError.verificationFailed("stable row for \(row.title)")
        }
        try control.click(windowFrame: readyCapture.frame,
                          local: CGPoint(x: readyLayout.titleX + 60, y: readyRow.y))
        do {
            try control.trackMenuAction("Import To Collection")
        } catch WatcherError.actionUnavailable {
            // Already in Collection, or the row could not be selected. Analyze Track must prove selection.
        }
        var analysisStarted = false
        var analysisAttempts = 0
        var postAnalysisIdle = 0
        var idleChecks = 0
        var absentChecks = 0
        for _ in 0..<240 {
            if paused { throw WatcherError.actionUnavailable("scan paused") }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let (updated, words) = try await snapshot()
            try requireOpenPlaylist(playlist, words: words, size: updated.frame.size)
            let currentLayout = try TableLayout.detect(words, size: updated.frame.size)
            guard let current = matchingRow(row, layout: currentLayout, words: words) else {
                absentChecks += 1
                if absentChecks < 30 || control.analysisBusy() { continue }
                throw WatcherError.verificationFailed("stable row for \(row.title) after import")
            }
            absentChecks = 0
            if (!row.missing.bpm && current.bpm != row.bpm) ||
               (!row.missing.key && current.key != row.key && current.key != "?" && row.key != "?") {
                logger.info("Preservation mismatch #\(row.number): original BPM=\(row.bpm, privacy: .public) key=\(row.key, privacy: .public), current BPM=\(current.bpm, privacy: .public) key=\(current.key, privacy: .public)")
                throw WatcherError.verificationFailed("preservation of existing BPM/key for \(row.title)")
            }
            if !current.missing.any,
               let bpm = Double(current.bpm.replacingOccurrences(of: ",", with: ".")), bpm > 0 {
                return current
            }
            if analysisStarted {
                if control.analysisBusy() { postAnalysisIdle = 0; continue }
                postAnalysisIdle += 1
                if postAnalysisIdle < 10 { continue }
                if analysisAttempts >= 2 {
                    throw WatcherError.verificationFailed("BPM and key for \(row.title) after two analyses")
                }
                // Rekordbox can write BPM while leaving KEY empty. Retry only
                // the still-missing field, keeping the new BPM and grid intact.
                try control.configureAnalysis(current.missing)
                analysisStarted = false
                idleChecks = 3
                postAnalysisIdle = 0
            }
            if control.analysisBusy() { idleChecks = 0; continue }
            idleChecks += 1
            if idleChecks < 3 { continue }
            guard control.isActive else { throw WatcherError.actionUnavailable("away analysis because Rekordbox lost focus") }
            do {
                // Import can leave a Collection row at 0% until Analyze Track is
                // explicitly invoked. Reselect it after the table has moved.
                try control.click(windowFrame: updated.frame,
                                  local: CGPoint(x: currentLayout.titleX + 60, y: current.y))
                try control.trackMenuAction("Analyze Track")
                try control.confirmAnalysisIfNeeded()
                analysisStarted = true
                analysisAttempts += 1
            } catch WatcherError.actionUnavailable {
                if idleChecks >= 5 && control.appleMusicAccountMismatchVisible() {
                    throw WatcherError.appleMusicAccountMismatch
                }
                if idleChecks >= 30 { throw WatcherError.actionUnavailable("Analyze Track for \(row.title)") }
            }
        }
        throw WatcherError.verificationFailed("BPM and key for \(row.title)")
    }

    private func restorePendingIfNeeded() throws {
        guard let data = defaults.data(forKey: recoveryKey) else { return }
        let settings = try JSONDecoder().decode(AnalysisPreferences.self, from: data)
        try control.restore(settings)
        defaults.removeObject(forKey: recoveryKey)
    }
}
