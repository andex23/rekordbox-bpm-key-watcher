# Rekordbox BPM Key Watcher

**Public beta · macOS 14 or later · Rekordbox 7**

An unofficial macOS menu bar utility for the currently open Apple Music playlist in Rekordbox 7. It checks that playlist's rows, imports tracks with missing BPM or key into the Collection, and asks Rekordbox to analyze only the missing fields. It verifies the BPM and key in the same playlist after analysis. It never opens or writes Rekordbox's database or downloads Apple Music audio.

## Download and install

Download the macOS universal app ZIP from [Releases](https://github.com/andex23/rekordbox-bpm-key-watcher/releases). Unzip it, move the app to `/Applications`, and open it. The ZIP contains both Apple silicon and Intel code. The app is ad hoc signed and **not notarized** because this project has no Apple Developer ID certificate. macOS may block the first launch; if you trust this source, follow [Apple's Open Anyway steps](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Do not disable Gatekeeper globally.

Grant **Accessibility** and **Screen & System Audio Recording** to the installed app in System Settings. Quit and reopen it if macOS requests a restart. Replacing or rebuilding an ad hoc signed app can require granting those permissions again.

## Run

Open the app from Applications. A small, draggable **BPM & Key** widget floats over Rekordbox while Rekordbox is active and visible. It hides when you switch apps. **Details…** opens the track table; the menu bar has the same controls. Nothing analyzes at launch or on a timer.

### One playlist

Open an Apple Music playlist, then choose **Start analysis of open playlist** from the BPM menu. A five-second countdown gives you time to step away. Keep the Mac unlocked and Rekordbox visible. Keyboard/mouse activity in another app, including Rekordbox, pauses automation; **Pause** also saves progress. Existing work in Rekordbox can finish while the watcher is paused.

**Check playlist** reads the rows without starting analysis. Keep Track Title, Artist, Key, BPM and track-number columns visible. Account access and analysis locks may only become known when an individual track is selected; preflight cannot certify every stream is playable.

The detail window shows Waiting, Importing, Analyzing, Complete, Failed and Paused states, values, attempts in the saved file, and errors. **Retry failed** or **Retry selected** rechecks live values before acting. A stalled import with no percentage progress for 60 seconds is reported and skipped. Each track gets at most two explicit analysis attempts per pass. Retry is user initiated; there is no infinite retry loop.

Progress is saved atomically under `~/Library/Application Support/Rekordbox BPM Key Watcher/`. Reopening the app loads the previous session. Open that same playlist and choose **Resume saved playlist**. Saved results are historical until checked again against Rekordbox; playlist position alone never authorizes reanalysis.

### All Apple Music playlists

Expand **Apple Music → Library → Playlists** in the sidebar and start **Analyze all Apple Music playlists**. The tool discovers visible sidebar entries, checks the heading after opening each playlist, processes its missing values, and saves a library queue. Duplicate/ambiguous names are reported instead of guessed. Collapsed folders and unreadable labels can prevent coverage; the report describes discovered playlists, not a guarantee that the whole Apple Music library was found.

Use **Resume saved library session** after an interruption. Completed tracks are checked and skipped even if they appear in another playlist. **Library progress / skipped playlists…** lists each playlist and any discovery errors; **Saved playlist results…** lets you view a saved playlist's results. This mode changes the visible playlist while running and attempts to return to the original playlist afterward.

### Completion and recovery

- **BPM ⋯**: working; inspect Details for progress.
- **BPM ✓**: every row in the current run was verified with positive BPM and a present key, with no errors (and no incomplete library jobs).
- **BPM !**: incomplete/error. Read the individual error before retrying.

The watcher uses Rekordbox's own analysis. It enables Auto Analysis while processing imports, configures only missing BPM/Grid and/or Key, disables Phrase/Vocal/Cue analysis, and saves previous settings once per session. It reopens Preferences only when the required analysis fields change. Settings are restored on a normal finish. If interrupted, recovery remains saved; **Restore previous analysis settings** restores them without starting another scan. The app does not take focus back automatically after user activity.

On a normal finish it attempts to restore identifiable selected rows and bring the original visible track back into view. Exact pixel scroll position, offscreen selections and prior column sort are not restored; the table may remain in track-number order. Interrupted sessions defer restoration rather than taking control back from you.

Rekordbox's [streaming guide](https://cdn.rekordbox.com/files/20260127164936/rekordbox7.2.10_streaming_service_usage_guide_EN.pdf) specifies importing streaming tracks one at a time and supports Auto Analysis after import. The tool still operates Rekordbox's interface. There is no verified invisible/background integration in this build. It does not write the Rekordbox database or extract Apple Music audio.

## Build and test

Command Line Tools with Swift 6.2 or newer are sufficient; Xcode is not required. `build.sh` builds for the Mac's current architecture with a macOS 14 deployment target.

```sh
./build.sh
swiftc -swift-version 5 Core.swift Tests/CoreTests.swift -o /tmp/rekordbox-watcher-core-tests
/tmp/rekordbox-watcher-core-tests
swiftc -swift-version 5 Session.swift Tests/SessionTests.swift -o /tmp/rekordbox-session-tests
/tmp/rekordbox-session-tests
```

The app uses macOS AppKit, Accessibility, ScreenCaptureKit, and Vision. The observed interface was Rekordbox 7.2.18 on macOS 26.6.2. A live scan identified all 31 rows in one already completed Apple Music playlist and skipped them with zero errors. In a 35-track playlist, 32 rows ultimately showed BPM and key after automated analysis or targeted retries; three rows remained unresolved, including streams that stayed at `0%`. Treat this release as experimental and check its results in Rekordbox before a set.

Rekordbox has no documented background analysis API for Apple Music tracks, so its analysis controls briefly appear while the away session runs. Menu placement and OCR may need adjustment after a Rekordbox UI update. Complete coverage of a playlist requires each Apple Music stream to be available to Rekordbox for analysis. Tracks that Rekordbox cannot access or has locked against analysis cannot be filled by this tool.

This project is independent and is not affiliated with AlphaTheta, Pioneer DJ, Apple, or Rekordbox. Released under the [MIT License](LICENSE).

### Playlist selection diagnostic fix (unreleased)

On 2026-09-27 a fresh capture showed Apple Music search results with the generic
`Apple Music` heading, not an open playlist. This revision detects that state
across three frames and asks for a playlist immediately, instead of displaying
“Waiting for Rekordbox playlist to redraw” for the entire retry interval.
The classifier passed both synthetic regression tests and replay of the actual
captured failure. CoreTests, SessionTests, the native build and signature checks
passed. This verifies the diagnostic fix; it does not establish successful BPM
or key analysis for the three previously incomplete tracks.

Starting a scan hides Details and library reports to avoid intercepting scroll
input. Opening Details during analysis pauses the watcher. Widget Minimize hides
it; Close pauses and hides it; reopening the application shows it again.

The installed build was then exercised live at 20:18 WAT. Both permissions
remained active. Within three seconds of activating Rekordbox it reported
“Apple Music search results are open. Select a playlist under Apple Music →
Library → Playlists, then start analysis.” No analysis was attempted in the
search view. The app was restarted in normal mode after this preflight check.
Full playlist analysis remains unverified pending an open playlist.
