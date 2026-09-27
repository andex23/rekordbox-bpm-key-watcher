import Foundation

@main
struct SessionTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("session.json"))
        let empty = try store.load()
        assert(empty == nil)
        let identity = TrackProgress.identity(number: 1, title: "Song", artist: "Artist")
        let working = TrackProgress(id: identity, number: 1, title: "Song", artist: "Artist", bpm: "0.00", key: "", phase: .analyzing, attempts: 2)
        let completed = TrackProgress(id: "2|other|artist", number: 2, title: "Other", artist: "Artist", bpm: "120.00", key: "Am", phase: .complete, verifiedAt: Date())
        let saved = SavedSession(playlist: "Test", total: 2, tracks: [working, completed])
        try store.save(saved)
        let restored = try store.load()!
        assert(restored.tracks[0].phase == .paused)
        assert(restored.tracks[0].attempts == 2)
        assert(restored.tracks[1].phase == .complete)
        assert(restored.tracks[1].bpm == "120.00")
        assert(restored.tracks[1].verifiedAt != nil)
        assert(identity != TrackProgress.identity(number: 1, title: "Different song", artist: "Artist"))
        assert(identity != TrackProgress.identity(number: 1, title: "Song", artist: "Different artist"))
        assert(identity != TrackProgress.identity(number: 2, title: "Song", artist: "Artist"))
        try Data("not JSON".utf8).write(to: store.url)
        do { _ = try store.load(); fatalError("Corrupt progress must not be treated as success") }
        catch is DecodingError { }
        print("SessionTests passed")
    }
}
