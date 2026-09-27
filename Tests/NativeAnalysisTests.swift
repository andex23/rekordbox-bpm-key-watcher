import Foundation
@main struct NativeAnalysisTests {
 static func main() throws {
  let normal = NativeAnalysisProfile(bpm: true, key: true, phrase: false, vocal: false, cue: false)
  assert(try! normal.command(for: .init(bpm: true, key: true)) == "Analyze Track")
  assert(try! normal.command(for: .init(bpm: false, key: true)) == "Analyze Key")
  assert(try! normal.command(for: .init(bpm: false, key: false)) == nil)
  do { _ = try normal.command(for: .init(bpm: true, key: false)); fatalError("Would overwrite key") } catch {}
  let bpmOnly = NativeAnalysisProfile(bpm: true, key: false, phrase: false, vocal: false, cue: false)
  assert(try! bpmOnly.command(for: .init(bpm: true, key: false)) == "Analyze Track")
  let unsafe = NativeAnalysisProfile(bpm: true, key: true, phrase: false, vocal: false, cue: true)
  do { _ = try unsafe.command(for: .init(bpm: true, key: true)); fatalError("Would modify cues") } catch {}
  do { _ = try NativeAnalysisProfile.parse(Data("<PROPERTIES/>".utf8)); fatalError("Missing flags accepted") } catch {}
  let xml = """
  <PROPERTIES>
   <VALUE name="trackAnalysisSettingsBpm" val="1"/>
   <VALUE name="enableKeyAnalysis" val="1"/>
   <VALUE name="trackAnalysisSettingsSongStruct" val="0"/>
   <VALUE name="trackAnalysisSettingsVocalDetect" val="0"/>
   <VALUE name="DetectCue" val="0"/>
   <VALUE name="Unrelated" val="ignored"/>
  </PROPERTIES>
  """
  let parsed = try NativeAnalysisProfile.parse(Data(xml.utf8))
  assert(parsed == normal)
  print("NativeAnalysisTests passed")
 }
}
