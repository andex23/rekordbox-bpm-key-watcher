import Foundation

// Read only: Rekordbox owns this file. Never patch it or its collection database.
struct NativeAnalysisProfile: Equatable {
    let bpm: Bool
    let key: Bool
    let phrase: Bool
    let vocal: Bool
    let cue: Bool

    static func read(from url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Pioneer/rekordbox6/rekordbox3.settings")) throws -> NativeAnalysisProfile {
        try parse(Data(contentsOf: url))
    }
    static func parse(_ data: Data) throws -> NativeAnalysisProfile {
        let delegate = AnalysisSettingsXML()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw WatcherError.missingLayout("saved Rekordbox analysis options") }
        func flag(_ name: String) throws -> Bool {
            guard let value = delegate.values[name], ["0", "1"].contains(value) else {
                throw WatcherError.missingLayout("saved analysis option \(name)")
            }
            return value == "1"
        }
        return try NativeAnalysisProfile(bpm: flag("trackAnalysisSettingsBpm"), key: flag("enableKeyAnalysis"),
            phrase: flag("trackAnalysisSettingsSongStruct"), vocal: flag("trackAnalysisSettingsVocalDetect"), cue: flag("DetectCue"))
    }
    func command(for missing: MissingFields) throws -> String? {
        guard missing.any else { return nil }
        if !missing.bpm { return "Analyze Key" }
        guard bpm else { throw WatcherError.actionUnavailable("BPM analysis: Rekordbox's saved BPM option is disabled") }
        guard !phrase && !vocal && !cue else {
            throw WatcherError.actionUnavailable("BPM analysis without also changing Phrase, Vocal, or Cue data; these options are enabled in Rekordbox")
        }
        guard missing.key || !key else {
            throw WatcherError.actionUnavailable("BPM-only analysis while preserving an existing key: Rekordbox's KEY option is enabled")
        }
        return "Analyze Track"
    }
}

private final class AnalysisSettingsXML: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private let names: Set<String> = ["trackAnalysisSettingsBpm", "enableKeyAnalysis", "trackAnalysisSettingsSongStruct", "trackAnalysisSettingsVocalDetect", "DetectCue"]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "VALUE", let name = attributes["name"], names.contains(name) { values[name] = attributes["val"] }
    }
}
