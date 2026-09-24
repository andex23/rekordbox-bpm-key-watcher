import Foundation
import CoreGraphics

@main
struct CoreTests {
    static func main() throws {
        func word(_ text: String, _ x: CGFloat, _ y: CGFloat) -> Word {
            Word(text: text, rect: CGRect(x: x, y: y, width: 70, height: 18), confidence: 1)
        }
        assert(TableLayout.bpmIsMissing("0.00"))
        assert(TableLayout.bpmIsMissing("0"))
        assert(!TableLayout.bpmIsMissing("124.00"))
        assert(!TableLayout.bpmIsMissing("126.87"))
        assert(!TableLayout.bpmIsMissing("unreadable"))
        assert(TableLayout.keyIsMissing(""))
        assert(!TableLayout.keyIsMissing("8A"))
        assert(!TableLayout.keyIsMissing("Bm"))
        let words = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("Genre", 1450, 1000),
            word("BPM", 1700, 1000), word("Playlists (2 Tracks)", 500, 1400),
            word("1", 400, 1040), word("First Track", 510, 1040), word("0.00", 1710, 1040),
            word("2", 400, 1070), word("Second Track", 510, 1070), word("8A", 1310, 1070), word("126.00", 1710, 1070),
            word("3", 400, 1100), word("Third Track", 510, 1100), word("7A", 1310, 1100), word("0.00", 1710, 1100),
            word("4", 400, 1130), word("Fourth Track", 510, 1130), word("128.00", 1710, 1130)
        ]
        let layout = try TableLayout.detect(words, size: CGSize(width: 2000, height: 1600))
        let withoutKeyHeader = words.filter { !($0.text == "Key" && $0.y == 1009) } + [word("Album", 1150, 1000)]
        let inferredKeyLayout = try TableLayout.detect(withoutKeyHeader, size: CGSize(width: 2000, height: 1600))
        assert(inferredKeyLayout.keyX > 1150 && inferredKeyLayout.keyX < 1450)
        let rows = layout.rows(words)
        assert(rows.count == 4)
        assert(rows[0].missing == MissingFields(bpm: true, key: true))
        assert(rows[1].missing == MissingFields(bpm: false, key: false))
        assert(rows[2].missing == MissingFields(bpm: true, key: false))
        assert(rows[3].missing == MissingFields(bpm: false, key: true))
        let starredWords = words.map { item in
            item.text == "0.00" && item.y < 1100 ? word("0.00 *", item.rect.minX, item.rect.minY) : item
        }
        assert(layout.rows(starredWords)[0].bpm == "0.00")
        let previewFallbackWords = [
            word("Preview", 382, 1000), word("Track Title", 650, 1000),
            word("Artist", 780, 1000), word("Key", 1040, 1000),
            word("BPM", 1300, 1000), word("0%", 290, 1040), word("7", 325, 1040),
            word("Example", 660, 1040), word("0.00", 1310, 1040)
        ]
        let fallbackLayout = try TableLayout.detect(previewFallbackWords, size: CGSize(width: 1440, height: 1500))
        assert(fallbackLayout.rows(previewFallbackWords).map(\.number) == [7])
        assert(fallbackLayout.rows(previewFallbackWords)[0].importPending)
        let missedFirstNumber = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("BPM", 1700, 1000),
            word("First", 510, 1020), word("0.00", 1710, 1020),
            word("2", 400, 1035), word("Second", 510, 1035), word("120.00", 1710, 1035),
            word("3", 400, 1050), word("Third", 510, 1050), word("125.00", 1710, 1050),
            word("4", 400, 1065), word("Fourth", 510, 1065), word("130.00", 1710, 1065)
        ]
        let inferredLayout = try TableLayout.detect(missedFirstNumber, size: CGSize(width: 2000, height: 1600))
        assert(inferredLayout.rows(missedFirstNumber).map(\.number) == [1, 2, 3, 4])
        let mostlyMissedNumbers = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("BPM", 1700, 1000)
        ] + (1...11).flatMap { number -> [Word] in
            let y = CGFloat(1010 + number * 15)
            let title = word("Track \(number)", 510, y)
            let bpm = word("120.00", 1710, y)
            return [title, bpm] + (number >= 10 ? [word(String(number), 400, y)] : [])
        }
        assert(inferredLayout.rows(mostlyMissedNumbers).map(\.number) == Array(1...11))
        let missingTitles = mostlyMissedNumbers.filter { !$0.text.hasPrefix("Track ") || $0.text == "Track Title" }
        assert(inferredLayout.rows(missingTitles).map(\.number) == Array(1...11))
        let driftingPitch = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("BPM", 1700, 1000),
            word("First Track", 510, 1049), word("120.00", 1710, 1049),
            word("8", 400, 1157), word("Eighth Track", 510, 1157), word("120.00", 1710, 1157),
            word("9", 400, 1173), word("Ninth Track", 510, 1173), word("120.00", 1710, 1173),
            word("10", 400, 1189), word("Tenth Track", 510, 1189), word("120.00", 1710, 1189)
        ]
        assert(inferredLayout.rows(driftingPitch).contains(where: { $0.number == 1 && $0.title == "First Track" }))
        let misalignedNumber = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("BPM", 1700, 1000),
            word("First Track", 510, 1040), word("120.00", 1710, 1040),
            word("2", 400, 1049.5), word("Second Track", 510, 1056), word("121.00", 1710, 1056),
            word("3", 400, 1070), word("Third Track", 510, 1070), word("122.00", 1710, 1070)
        ]
        let misalignedRows = inferredLayout.rows(misalignedNumber)
        if misalignedRows.map(\.number) != [1, 2, 3] {
            fatalError(String(describing: misalignedRows.map { "\($0.number):\($0.title)@\($0.y)" }))
        }
        let missedLastNumber = [
            word("#", 400, 1000), word("Track Title", 500, 1000), word("Artist", 900, 1000),
            word("Key", 1300, 1000), word("BPM", 1700, 1000),
            word("28", 400, 1025), word("Third Last", 510, 1025), word("119.00", 1710, 1025),
            word("29", 400, 1040), word("Penultimate", 510, 1040), word("120.00", 1710, 1040),
            word("30", 400, 1055), word("Before Last", 510, 1055), word("121.00", 1710, 1055),
            word("Last Track", 510, 1070), word("122.00", 1710, 1070),
            word("1", 400, 1100), // A bad OCR number elsewhere must not hide the last row.
            word("Bad Number", 510, 1100)
        ]
        assert(inferredLayout.rows(missedLastNumber).contains(where: { $0.number == 31 && $0.title.contains("Last Track") }))
        assert(!inferredLayout.rows(missedLastNumber).contains(where: { $0.number == 1 }))
        assert(PlaylistList.name(fromHeading: "Anje (86 Tracks)") == "Anje")
        assert(PlaylistList.name(fromHeading: "Zions playlist 1 (0 Track)") == "Zions playlist 1")
        assert(PlaylistList.name(fromHeading: "Example Playlist (31 Tracks)") == "Example Playlist")
        assert(PlaylistList.count(fromHeading: "Example Playlist (31 Tracks)") == 31)
        assert(PlaylistList.count(fromHeading: "Zions playlist 1 (0 Track)") == 0)
        assert(PlaylistList.name(fromHeading: "Collection") == nil)
        print("CoreTests passed")
    }
}
