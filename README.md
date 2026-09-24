# Rekordbox BPM Key Watcher

**Public beta · macOS 14 or later · Rekordbox 7**

An unofficial macOS menu bar utility for the currently open Apple Music playlist in Rekordbox 7. It checks that playlist's rows, imports tracks with missing BPM or key into the Collection, and asks Rekordbox to analyze only the missing fields. It verifies the BPM and key in the same playlist after analysis. It never opens or writes Rekordbox's database or downloads Apple Music audio.

## Download and install

Download the macOS universal app ZIP from [Releases](https://github.com/andex23/rekordbox-bpm-key-watcher/releases). Unzip it, move the app to `/Applications`, and open it. The ZIP contains both Apple silicon and Intel code. The app is ad hoc signed and **not notarized** because this project has no Apple Developer ID certificate. macOS may block the first launch; if you trust this source, follow [Apple's Open Anyway steps](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Do not disable Gatekeeper globally.

Grant **Accessibility** and **Screen & System Audio Recording** to the installed app in System Settings. Quit and reopen it if macOS requests a restart. Replacing or rebuilding an ad hoc signed app can require granting those permissions again.

## Run

Open `Rekordbox BPM Key Watcher.app`. Its `♪ BPM` menu has **Grant permissions…**, **Analyze open playlist while away**, **Stop analysis**, a progress summary, and recent errors.

Open the Apple Music playlist you want analyzed, then choose **Analyze open playlist while away** before stepping away. Nothing scans at launch or on a timer. The watcher stays on that playlist. It scrolls its track table and, if needed, sorts by track number so it can verify every row; it never opens another playlist. The table remains sorted by track number afterward. If Rekordbox loses focus, the watcher stops. **Stop analysis** also ends the session. Do not use Rekordbox during an away session. The app does not start automatically at Mac login.

For a new set where every track needs the same fields, the watcher first reads every row and confirms the playlist track count, then selects the entire playlist and runs Rekordbox's **Import To Collection** and **Analyze Track** once each. It waits for that batch to finish and checks every resulting BPM and key. If the playlist contains a mix of completed and missing fields, it processes only the missing tracks individually so existing values and grids remain safe. Rekordbox still needs time to analyze each audio stream internally, but the watcher no longer opens the menus once per track for a uniform set.

The tool changes Rekordbox's track-analysis toggles while processing a track. It saves the previous BPM/Grid, Key, Phrase, Vocal, Auto Analysis, and Cue Analysis settings, then restores them after each track. If interrupted, it tries to restore them when the next away session starts.

When a row, menu action, or result cannot be identified confidently, it reports an error and skips further action on that row. A track counts as analyzed only after a positive BPM and filled key appear in Rekordbox's playlist. Its OCR layout expects the **Track Title**, **Artist**, **Key**, **BPM**, and track-number columns to be visible in the Apple Music playlist view. Keep those columns visible. The open playlist must have an identifiable name in the track-list heading.

If Rekordbox reports that a track is managed by a different Apple Music account, the watcher skips that row and shows the error. Rekordbox will not analyze that track until the Apple Music account in Rekordbox can access it.

Import may leave an Apple Music row at `0%` without filling its fields. The watcher then selects **Track → Analyze Track**, confirms the analysis settings, and waits for Rekordbox to write the result into the playlist. A single-letter key that Vision fails to transcribe is still treated as filled when the key cell visibly contains text, avoiding repeat analysis of completed tracks.

## Build and test

Command Line Tools with Swift 6.2 or newer are sufficient; Xcode is not required. `build.sh` builds for the Mac's current architecture with a macOS 14 deployment target.

```sh
./build.sh
swiftc -swift-version 5 Core.swift Tests/CoreTests.swift -o /tmp/rekordbox-watcher-core-tests
/tmp/rekordbox-watcher-core-tests
```

The app uses macOS AppKit, Accessibility, ScreenCaptureKit, and Vision. The observed interface was Rekordbox 7.2.18 on macOS 26.6.2. A live scan identified all 31 rows in one already completed Apple Music playlist and skipped them with zero errors. The one-command batch path has **not** yet been live-tested on a fresh playlist where every track is blank. Treat this release as experimental and check its results in Rekordbox before a set.

Rekordbox has no documented background analysis API for Apple Music tracks, so its analysis controls briefly appear while the away session runs. Menu placement and OCR may need adjustment after a Rekordbox UI update. Complete coverage of a playlist requires each Apple Music stream to be available to Rekordbox for analysis. Tracks that Rekordbox cannot access or has locked against analysis cannot be filled by this tool.

This project is independent and is not affiliated with AlphaTheta, Pioneer DJ, Apple, or Rekordbox. Released under the [MIT License](LICENSE).
