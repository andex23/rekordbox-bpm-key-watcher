# Rekordbox BPM Key Watcher

**Public beta · macOS 14 or later · Rekordbox 7**

An unofficial macOS menu bar utility for the currently open Apple Music playlist in Rekordbox 7. It checks that playlist's rows, imports tracks with missing BPM or key into the Collection, and asks Rekordbox to analyze only the missing fields. It verifies the BPM and key in the same playlist after analysis. It never opens or writes Rekordbox's database or downloads Apple Music audio.

## Download and install

Download the macOS universal app ZIP from [Releases](https://github.com/andex23/rekordbox-bpm-key-watcher/releases). Unzip it, move the app to `/Applications`, and open it. The ZIP contains both Apple silicon and Intel code. The app is ad hoc signed and **not notarized** because this project has no Apple Developer ID certificate. macOS may block the first launch; if you trust this source, follow [Apple's Open Anyway steps](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Do not disable Gatekeeper globally.

Grant **Accessibility** and **Screen & System Audio Recording** to the installed app in System Settings. Quit and reopen it if macOS requests a restart. Replacing or rebuilding an ad hoc signed app can require granting those permissions again.

## Run

Open the app from Applications. A small, draggable **BPM & Key** widget floats over Rekordbox while Rekordbox is active and visible. It hides when you switch apps. **Details…** opens the track table; the menu bar has the same controls. Nothing analyzes at launch or on a timer.

### One playlist

Open an Apple Music playlist, then choose **Start analysis of open playlist** from the BPM menu. A five-second countdown gives you time to step away. Keep the Mac unlocked and Rekordbox visible. Clicks, scrolling, and keyboard input in another app, including Rekordbox, pause automation; mouse movement alone does not; **Pause** also saves progress. Existing work in Rekordbox can finish while the watcher is paused.

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

The watcher uses Rekordbox's native **Analyze Track** and **Analyze Key** commands. Normal analysis does not change Preferences or enable Auto Analysis. It reads only the saved analysis-option flags to check whether the native command is compatible with preserving existing data; it never edits that settings file. Key-only work uses Analyze Key and does not reanalyze BPM/Grid. If BPM is missing but a key exists and Rekordbox's KEY option is enabled, or Phrase/Vocal/Cue analysis is enabled, the tool reports the incompatible options instead of silently overwriting data. Saved settings can be stale if they were changed in Rekordbox without being persisted; verify results before relying on the tool.

A pending settings recovery from an older watcher build is restored once when resuming. New native-command runs do not create a recovery record or repeatedly open Preferences. The separate **Restore previous analysis settings** command remains for old interrupted sessions.

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

### Current playlist and OCR fixes (unreleased)

The widget and Details **Analyze playlist** button always analyze the currently
open playlist. Only the explicit saved-session menu and targeted retry controls
require the saved playlist. Normal analysis first reads the playlist to group contiguous unfinished tracks
with matching missing fields. Completed tracks split those groups and are excluded.
All eligible groups are submitted through Rekordbox's native analysis command
before waiting for the queue; its reported remaining-track count is shown. A
restart waits for existing analysis instead of submitting duplicate work. Then every
row is checked again; remaining failures are handled individually. **Check playlist** still reads the entire list.
The reader retries a tighter browser crop when deck graphics cause Vision to
miss the table. Scrolling to the top now checks actual row progress instead of
stopping after 20 scrolls. Mouse movement alone no longer pauses analysis;
clicks, keyboard input and scrolling pause active UI control. They do not pause
the passive wait after Rekordbox has accepted an analysis queue. Green played-track key text is
recognized as present even if its letter is missed by OCR.

Live verification on 2026-09-27: Private-School Piano was read at 156/156 rows.
Tracks 1–4 were manually analyzed by the user and are not evidence of automated
analysis. The tool then imported and analyzed track 5, Iphupho, from 0.00 BPM
and blank key to 112.00 BPM and Am at 20:37 WAT. The isolated run finished with
one analyzed, three skipped and zero errors, restored settings, and the result
was confirmed in a fresh Rekordbox capture. This verifies one automatic
analysis, not completion of the remaining 151 tracks.


### Native-command investigation and live test

Read-only inspection of the installed Rekordbox bundle found the native Analyze Track/Analyze Key commands and a `rekordboxdj` URL scheme, but did not identify a callable background analysis endpoint. No executable patching, injection, audio extraction or collection-database writes were used. The implementation uses the existing application commands and reads a whitelist of analysis-option flags from its XML settings.

On 2026-09-27 at 20:49 WAT, the native-command path changed track 13, Amantombazane, from 0.00 BPM and blank key to 113.00 BPM and Am. Preferences opened once before that run to restore the previous version's pending settings; they did not open while processing tracks 13 and 14. Track 14, Ama hem hem, subsequently changed from blank fields to 113.00 BPM and B (the key was independently checked in the captured playlist). This is still visible UI automation, not an invisible background service.

A fresh launch at 20:54 WAT performed no Preferences recovery or settings changes. It analyzed track 15, uMoya 2.0, from 0.00 BPM and blank key to 113.00 BPM and Bm at 20:55 WAT, with one analyzed, fourteen existing complete tracks skipped, and zero errors. CoreTests, SessionTests, NativeAnalysisTests and the final signed build passed. This remains a partial playlist verification; all 156 tracks have not been completed. Partial runs now explicitly report that the playlist is incomplete.

### Full-playlist completion repair (under live verification)

Normal scans now use batches without the old experimental flag. Batch selection
is checked against Rekordbox's selected-track count, and no Preferences changes
are used. Selection and scrolling release modifier flags explicitly. The scanner
also handles either direction of the track-number sort before requiring row 1.
A captured failure revealed that variable-height tiny number glyphs caused the
row-spacing estimate to drift, incorrectly assigning song 2 to row 1. Row spacing
now uses repeated title baselines when available. A regression test and replay of
the failing capture both identify the first three tracks correctly.

Full-playlist completion is being verified on Private-School Piano (156 tracks).
Do not treat the earlier single-track tests as whole-playlist completion.

Live batch evidence on 2026-09-27: Rekordbox accepted 46 previously missing
tracks, and a subsequent complete preflight verified BPM/key populated for rows
1–63. A 93-track selection was rejected, so batches are now capped at 32, with
bounded retries and recursive splitting of disabled selections. Rekordbox
accepted the remaining groups of 32, 32 and 29 at 21:25–21:26 WAT. Its native
remaining-track count then decreased from 93 while the watcher waited without
controlling the UI. Final all-row verification is still required.
