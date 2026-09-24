import AppKit
import Vision
import ScreenCaptureKit

struct Word: Equatable {
    let text: String
    let rect: CGRect // Window-local points, origin at the upper left.
    let confidence: Float
    var x: CGFloat { rect.midX }
    var y: CGFloat { rect.midY }
}

struct CapturedWindow {
    let image: CGImage
    let frame: CGRect // Screen points, origin at the upper left.
}

enum WatcherError: LocalizedError {
    case noRekordbox
    case windowHidden
    case macLocked
    case missingLayout(String)
    case actionUnavailable(String)
    case verificationFailed(String)
    case appleMusicAccountMismatch
    var errorDescription: String? {
        switch self {
        case .noRekordbox: return "Rekordbox is not running."
        case .windowHidden: return "Rekordbox must be visible to scan playlists."
        case .macLocked: return "Mac appears locked. Unlock it, keep Rekordbox visible, and start the scan again."
        case .missingLayout(let value): return "Could not identify \(value) in the Rekordbox window."
        case .actionUnavailable(let value): return "Rekordbox did not enable \(value)."
        case .verificationFailed(let value): return "Could not verify \(value)."
        case .appleMusicAccountMismatch: return "Apple Music account mismatch: Rekordbox says this track belongs to a different Apple Music account. Sign in with the account that owns this playlist, then try again."
        }
    }
}

struct MissingFields: Equatable {
    let bpm: Bool
    let key: Bool
    var any: Bool { bpm || key }
}

struct TrackRow {
    let number: Int
    let title: String
    let bpm: String
    let key: String
    let y: CGFloat
    let missing: MissingFields
    let importPending: Bool
}

enum PlaylistList {
    static func count(fromHeading heading: String) -> Int? {
        guard let match = heading.range(of: "[0-9]+(?= Tracks?\\))", options: .regularExpression) else { return nil }
        return Int(heading[match])
    }
    static func name(fromHeading heading: String) -> String? {
        guard heading.range(of: "\\([0-9]+ Tracks?\\)", options: .regularExpression) != nil else { return nil }
        let name = heading.replacingOccurrences(of: "\\s*\\([0-9]+ Tracks?\\).*", with: "", options: .regularExpression)
        return name.isEmpty ? nil : name
    }
}

struct TableLayout {
    let numberX: CGFloat
    let titleX: CGFloat
    let artistX: CGFloat
    let keyX: CGFloat
    let keyEndX: CGFloat
    let bpmX: CGFloat
    let bpmEndX: CGFloat
    let headerY: CGFloat
    let bottomY: CGFloat

    static func detect(_ words: [Word], size: CGSize) throws -> TableLayout {
        let title = words.first { $0.text.localizedCaseInsensitiveContains("Track Title") && $0.y > size.height * 0.35 }
        let bpm = words.first { $0.text == "BPM" && $0.y > size.height * 0.35 }
        guard let title, let bpm else { throw WatcherError.missingLayout("Track Title and BPM columns") }
        let sameLine = words.filter { abs($0.y - title.y) < 16 }
        let genre = sameLine.first { $0.text == "Genre" }
        let album = sameLine.first { $0.text == "Album" }
        let key = sameLine.first { $0.text == "Key" }
        // Vision intermittently drops the thin "Key" header even though the
        // adjacent Album and Genre headers remain. Their midpoint is the
        // left edge of Key in Rekordbox's evenly spaced table layout.
        let keyX = key?.rect.minX ?? ((album != nil && genre != nil) ? (album!.rect.minX + genre!.rect.minX) / 2 : nil)
        guard let keyX, title.rect.minX < keyX, keyX < bpm.rect.minX else {
            throw WatcherError.missingLayout("Key column between Album and Genre")
        }
        let artist = sameLine.first { $0.text == "Artist" }
        guard let artist, title.x < artist.x, artist.x < keyX else { throw WatcherError.missingLayout("Artist column") }
        let number = sameLine.first { $0.text == "#" || $0.text == "No." }
        let preview = sameLine.first { $0.text == "Preview" }
        guard let numberX = number?.x ?? preview.map({ $0.rect.minX - 55 }) else {
            throw WatcherError.missingLayout("track number column")
        }
        let rating = sameLine.first { $0.text.hasPrefix("Ratin") && $0.x > bpm.x }
        let nextPanel = words.filter { $0.y > title.y + 70 && $0.x > size.width * 0.18 && ($0.text.hasPrefix("Playlists (") || $0.text == "Tree View") }.map(\.y).min()
        let bottom = min(nextPanel ?? size.height * 0.93, size.height * 0.93)
        return TableLayout(numberX: numberX, titleX: title.rect.minX, artistX: artist.rect.minX,
                           keyX: keyX, keyEndX: genre?.rect.minX ?? (keyX + 140),
                           bpmX: bpm.rect.minX, bpmEndX: rating?.rect.minX ?? min(size.width - 10, bpm.rect.minX + 90),
                           headerY: title.y, bottomY: bottom)
    }

    func rows(_ words: [Word]) -> [TrackRow] {
        var numbers = words.compactMap { word -> (Int, CGFloat)? in
            guard word.y > headerY + 8, word.y < bottomY - 6,
                  abs(word.x - numberX) < 35,
                  let number = Int(word.text), number > 0, number < 100_000 else { return nil }
            return (number, word.y)
        }
        let ordered = numbers.sorted { $0.1 < $1.1 }
        let steps = zip(ordered, ordered.dropFirst()).compactMap { a, b -> CGFloat? in
            let distance = b.1 - a.1
            return b.0 == a.0 + 1 && distance >= 10 && distance <= 20 ? distance : nil
        }
        // Infer a missed tiny number from two nearby numbered rows. OCR can
        // invent one bad number elsewhere in the viewport; that must not hide
        // a real row at the top or bottom of the table.
        if !steps.isEmpty {
            let pitch = steps.sorted()[steps.count / 2]
            let supported = ordered.filter { anchor in
                ordered.contains { neighbor in
                    let difference = neighbor.0 - anchor.0
                    return difference != 0 && abs(difference) <= 12 &&
                        abs((neighbor.1 - anchor.1) - CGFloat(difference) * pitch) < 3
                }
            }
            if supported.count >= 2 { numbers = supported }
            for title in words where title.y > headerY + 8 && title.y < bottomY - 6 &&
                title.x >= titleX && title.x < artistX {
                guard !numbers.contains(where: { abs($0.1 - title.y) < 7 }) else { continue }
                let votes = supported.compactMap { anchor -> Int? in
                    let offset = (title.y - anchor.1) / pitch
                    let step = Int(offset.rounded())
                    guard abs(step) <= 12, abs(offset - CGFloat(step)) < 0.35 else { return nil }
                    return anchor.0 + step
                }
                let candidates = Dictionary(grouping: votes, by: { $0 })
                guard let winner = candidates.max(by: { $0.value.count < $1.value.count }),
                      winner.value.count >= 2, winner.key > 0, winner.key < 100_000,
                      !numbers.contains(where: { $0.0 == winner.key }) else { continue }
                numbers.append((winner.key, title.y))
            }
            // Some rows have both the tiny number and title omitted by Vision
            // in its full-window pass. When several neighboring numbers prove
            // ascending playlist order, recover the row slot and read its BPM
            // cell at that exact position. This also covers a completely
            // analyzed track whose title remains hard to transcribe.
            if supported.count >= 2, let anchor = supported.first {
                for step in -12...12 {
                    let number = anchor.0 + step
                    let y = anchor.1 + CGFloat(step) * pitch
                    guard number > 0, number < 100_000,
                          y > headerY + 8, y < bottomY - 6,
                          !numbers.contains(where: { $0.0 == number || abs($0.1 - y) < 7 }) else { continue }
                    let candidate = row(number: number, y: y, words: words)
                    let hasBpm = Double(candidate.bpm.replacingOccurrences(of: ",", with: ".")) != nil
                    if !candidate.title.isEmpty || hasBpm { numbers.append((number, y)) }
                }
            }
        }
        // A long projection from rows near the bottom of the viewport can
        // drift by a few pixels at the very first row. Use two adjacent rows
        // already identified in this same capture to recover that neighbor.
        if !numbers.contains(where: { $0.0 == 1 }),
           let second = numbers.first(where: { $0.0 == 2 }),
           let third = numbers.first(where: { $0.0 == 3 }) {
            let secondTitle = row(number: 2, y: second.1, words: words).title
            let thirdTitle = row(number: 3, y: third.1, words: words).title
            let titleWords = words.filter { $0.x >= titleX && $0.x < artistX }
            let secondY = titleWords.first(where: { $0.text == secondTitle })?.y
            let thirdY = titleWords.first(where: { $0.text == thirdTitle })?.y
            if let secondY, let thirdY, thirdY - secondY >= 10, thirdY - secondY <= 20 {
              let y = secondY - (thirdY - secondY)
              if y > headerY + 8, y < bottomY - 6 {
                let candidate = row(number: 1, y: y, words: words)
                let hasBpm = Double(candidate.bpm.replacingOccurrences(of: ",", with: ".")) != nil
                if !candidate.title.isEmpty || hasBpm { numbers.append((1, y)) }
              }
            }
        }
        return numbers.map { number, y in
            row(number: number, y: y, words: words)
        }.filter { !$0.title.isEmpty || Double($0.bpm.replacingOccurrences(of: ",", with: ".")) != nil }
            .sorted { $0.number < $1.number }
    }

    func row(number: Int, y: CGFloat, words: [Word]) -> TrackRow {
            func inCell(_ start: CGFloat, _ end: CGFloat) -> [Word] {
                // Rekordbox rows are about 15 points tall. A wider tolerance
                // can read the next row's BPM/key into this track.
                words.filter { abs($0.y - y) < 7 && $0.x >= start && $0.x < end }
                    .sorted { $0.x < $1.x }
            }
            let title = inCell(titleX, artistX).map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let key = inCell(keyX, keyEndX).map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let rawBpm = inCell(bpmX, bpmEndX).map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let bpm = rawBpm.range(of: "^[0-9]+(?:[.,][0-9]+)?", options: .regularExpression)
                .map { String(rawBpm[$0]) } ?? rawBpm
            let missing = MissingFields(bpm: Self.bpmIsMissing(bpm), key: Self.keyIsMissing(key))
            let importPending = words.contains {
                abs($0.y - y) < 7 && $0.x > numberX - 50 && $0.x < numberX &&
                $0.text.range(of: "^[0-9]{1,3}%$", options: .regularExpression) != nil
            }
            return TrackRow(number: number, title: title, bpm: bpm, key: key, y: y,
                            missing: missing, importPending: importPending)
    }

    static func bpmIsMissing(_ value: String) -> Bool {
        let cleaned = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let bpm = Double(cleaned) else { return false } // Unreadable is uncertain, not zero.
        return bpm == 0
    }

    static func keyIsMissing(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "-" || cleaned == "--"
    }
}

final class WindowReader {
    let bundleIdentifier = "com.pioneerdj.rekordboxdj"

    func capture() async throws -> CapturedWindow {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            throw WatcherError.noRekordbox
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows
            .filter({ $0.owningApplication?.processID == app.processIdentifier && $0.frame.width > 600 && $0.frame.height > 400 })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw WatcherError.windowHidden
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * 2))
        configuration.height = max(1, Int(window.frame.height * 2))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedWindow(image: image, frame: window.frame)
    }

    func recognize(_ captured: CapturedWindow) throws -> [Word] {
        // Vision can choose a 180-degree text orientation for Rekordbox's
        // full performance window and ignore the browser table altogether.
        // The playlist and track table live in the lower half; recognizing
        // that region alone keeps Vision oriented to the rows we need.
        let image = captured.image
        let cropY = Int(Double(image.height) * 0.5)
        guard let browserImage = image.cropping(to: CGRect(x: 0, y: cropY,
                                                            width: image.width, height: image.height - cropY)) else {
            throw WatcherError.windowHidden
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: browserImage).perform([request])
        let size = captured.frame.size
        let scaleX = size.width / CGFloat(image.width)
        let scaleY = size.height / CGFloat(image.height)
        var words: [Word] = (request.results ?? []).compactMap { result in
            guard let match = result.topCandidates(1).first else { return nil }
            let box = result.boundingBox
            let rect = CGRect(x: box.minX * CGFloat(browserImage.width) * scaleX,
                              y: (CGFloat(cropY) + (1 - box.maxY) * CGFloat(browserImage.height)) * scaleY,
                              width: box.width * CGFloat(browserImage.width) * scaleX,
                              height: box.height * CGFloat(browserImage.height) * scaleY)
            return Word(text: match.string, rect: rect, confidence: match.confidence)
        }
        // Vision occasionally omits a one-character key (for example F) in a
        // full-window pass. A lit glyph in that otherwise empty cell means the
        // key is present; never re-analyze a completed track because of OCR.
        if let layout = try? TableLayout.detect(words, size: size) {
            words += recognizeTrackTitles(captured.image, size: size, layout: layout, existing: words)
            words += recognizeTrackNumbers(captured.image, size: size, layout: layout, existing: words)
            words += recognizeBPMValues(captured.image, size: size, layout: layout, existing: words)
            for row in layout.rows(words) where row.key.isEmpty {
                if keyCellHasGlyph(captured.image, size: size, layout: layout, row: row) {
                    words.append(Word(text: "?", rect: CGRect(x: layout.keyX + 8, y: row.y - 8,
                                                              width: 24, height: 16), confidence: 0))
                }
            }
        }
        return words
    }

    private func recognizeBPMValues(_ image: CGImage, size: CGSize, layout: TableLayout,
                                    existing: [Word]) -> [Word] {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let area = CGRect(x: layout.bpmX * scaleX,
                          y: (layout.headerY + 7) * scaleY,
                          width: (layout.bpmEndX - layout.bpmX - 2) * scaleX,
                          height: (layout.bottomY - layout.headerY - 13) * scaleY).integral
        guard area.width > 0, area.height > 0, let crop = image.cropping(to: area) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do { try VNImageRequestHandler(cgImage: crop).perform([request]) }
        catch { return [] }
        return (request.results ?? []).compactMap { result in
            guard let match = result.topCandidates(1).first,
                  match.string.range(of: "^[0-9]+(?:[.,][0-9]+)?", options: .regularExpression) != nil else { return nil }
            let box = result.boundingBox
            let rect = CGRect(x: area.minX / scaleX + box.minX * area.width / scaleX,
                              y: area.minY / scaleY + (1 - box.maxY) * area.height / scaleY,
                              width: box.width * area.width / scaleX,
                              height: box.height * area.height / scaleY)
            guard !existing.contains(where: { $0.x >= layout.bpmX && $0.x < layout.bpmEndX &&
                abs($0.y - rect.midY) < 7 }) else { return nil }
            return Word(text: match.string, rect: rect, confidence: match.confidence)
        }
    }

    private func recognizeTrackTitles(_ image: CGImage, size: CGSize, layout: TableLayout,
                                      existing: [Word]) -> [Word] {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let area = CGRect(x: layout.titleX * scaleX,
                          y: (layout.headerY + 7) * scaleY,
                          width: (layout.artistX - layout.titleX - 2) * scaleX,
                          height: (layout.bottomY - layout.headerY - 13) * scaleY).integral
        guard area.width > 0, area.height > 0, let crop = image.cropping(to: area) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do { try VNImageRequestHandler(cgImage: crop).perform([request]) }
        catch { return [] }
        return (request.results ?? []).compactMap { result in
            guard let match = result.topCandidates(1).first, !match.string.isEmpty else { return nil }
            let box = result.boundingBox
            let rect = CGRect(x: area.minX / scaleX + box.minX * area.width / scaleX,
                              y: area.minY / scaleY + (1 - box.maxY) * area.height / scaleY,
                              width: box.width * area.width / scaleX,
                              height: box.height * area.height / scaleY)
            guard !existing.contains(where: { $0.x >= layout.titleX && $0.x < layout.artistX &&
                abs($0.y - rect.midY) < 7 }) else { return nil }
            return Word(text: match.string, rect: rect, confidence: match.confidence)
        }
    }

    private func recognizeTrackNumbers(_ image: CGImage, size: CGSize, layout: TableLayout,
                                       existing: [Word]) -> [Word] {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let area = CGRect(x: (layout.numberX - 18) * scaleX,
                          y: (layout.headerY + 7) * scaleY,
                          width: 48 * scaleX,
                          height: (layout.bottomY - layout.headerY - 13) * scaleY).integral
        guard area.width > 0, area.height > 0, let crop = image.cropping(to: area) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do { try VNImageRequestHandler(cgImage: crop).perform([request]) }
        catch { return [] }
        return (request.results ?? []).compactMap { result in
            guard let match = result.topCandidates(1).first,
                  let number = Int(match.string), number > 0, number < 100_000 else { return nil }
            let box = result.boundingBox
            let rect = CGRect(x: area.minX / scaleX + box.minX * area.width / scaleX,
                              y: area.minY / scaleY + (1 - box.maxY) * area.height / scaleY,
                              width: box.width * area.width / scaleX,
                              height: box.height * area.height / scaleY)
            guard abs(rect.midX - layout.numberX) < 35,
                  !existing.contains(where: { Int($0.text) == number && abs($0.y - rect.midY) < 8 }) else { return nil }
            return Word(text: match.string, rect: rect, confidence: match.confidence)
        }
    }

    private func keyCellHasGlyph(_ image: CGImage, size: CGSize, layout: TableLayout, row: TrackRow) -> Bool {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        let area = CGRect(x: (layout.keyX - 2) * scaleX,
                          y: (row.y - 6.5) * scaleY,
                          width: min(85, layout.keyEndX - layout.keyX - 4) * scaleX,
                          height: 13 * scaleY).integral
        guard area.width > 0, area.height > 0, let crop = image.cropping(to: area) else { return false }
        let width = crop.width, height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        var bright = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[pixel] > 150 && pixels[pixel + 1] > 150 && pixels[pixel + 2] > 150 {
                bright += 1
                if bright >= 16 { return true }
            }
        }
        return false
    }
}
