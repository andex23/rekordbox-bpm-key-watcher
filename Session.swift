import Foundation

enum TrackPhase: String, Codable {
    case waiting = "Waiting", importing = "Importing", analyzing = "Analyzing"
    case complete = "Complete", failed = "Failed", paused = "Paused"
}

struct TrackProgress: Codable, Identifiable {
    let id: String
    let number: Int
    let title: String
    let artist: String
    var bpm: String
    var key: String
    var phase: TrackPhase = .waiting
    var detail = ""
    var attempts = 0
    var verifiedAt: Date?

    static func identity(number: Int, title: String, artist: String) -> String {
        // Position alone is not identity: playlists can be reordered between runs.
        "\(number)|\(title.lowercased())|\(artist.lowercased())"
    }
}

struct SavedSession: Codable {
    var version = 1
    var playlist: String
    var total: Int
    var updatedAt = Date()
    var tracks: [TrackProgress]
    var bookmark: PlaylistBookmark?

    mutating func recoverInterruptedWork() {
        for i in tracks.indices where tracks[i].phase == .importing || tracks[i].phase == .analyzing {
            tracks[i].phase = .paused
            tracks[i].detail = "Interrupted. Resume to check the live values before retrying."
        }
    }
}

struct SessionStore {
    let url: URL
    static var standard: SessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SessionStore(url: base.appendingPathComponent("Rekordbox BPM Key Watcher/session.json"))
    }
    func load() throws -> SavedSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var saved = try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: url))
        guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        saved.recoverInterruptedWork()
        return saved
    }
    func save(_ session: SavedSession) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }
}

struct PlaylistBookmark: Codable {
    struct Row: Codable {
        let number: Int
        let title: String
        let artist: String
    }
    let top: Row
    let selected: [Row]
}

struct PlaylistJob: Codable {
    var label: String
    var name: String
    var state = "Waiting"
    var error = ""
    var result: SavedSession?
}
struct LibraryQueue: Codable {
    var originalPlaylist: String?
    var jobs: [PlaylistJob] = []
    var discoveryErrors: [String] = []
}
