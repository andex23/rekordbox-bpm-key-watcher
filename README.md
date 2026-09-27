# Rekordbox BPM Key Watcher

A free, open-source macOS utility that asks **Rekordbox 7 to fill missing BPM and key fields in Apple Music playlists**. Includes a small floating widget, menu bar controls, batch analysis and saved progress.

**Public beta · macOS 14+ · Apple silicon and Intel · MIT licensed**

## Download

**[Download v0.1.0-beta.5 for macOS](https://github.com/andex23/rekordbox-bpm-key-watcher/releases/download/v0.1.0-beta.5/Rekordbox-BPM-Key-Watcher-v0.1.0-beta.5-macOS-universal.zip)**

[All releases](https://github.com/andex23/rekordbox-bpm-key-watcher/releases) · [Report a problem](https://github.com/andex23/rekordbox-bpm-key-watcher/issues)

Download the **macOS-universal.zip** asset, not GitHub's “Source code” ZIP. No Xcode, terminal commands or separate runtime are needed to run the downloaded app.

## Install or update

1. Quit any older **Rekordbox BPM Key Watcher** from its BPM menu. Leave Rekordbox itself installed.
2. Download and unzip the release. Open the extracted folder.
3. Drag **Rekordbox BPM Key Watcher.app** into **Applications**. Choose **Replace** if updating. Keep one installed copy; remove older copies from Downloads or elsewhere.
4. Open the app from **Applications**. It appears in the menu bar; the widget appears when Rekordbox is visible and active.
5. If macOS blocks the first launch, the app is **ad hoc signed, not Developer ID signed or notarized**. If you trust this download, use **System Settings → Privacy & Security → Open Anyway**, following [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Do not disable Gatekeeper globally.
6. Under **System Settings → Privacy & Security**, enable the installed watcher in both:
   - **Accessibility** — operates Rekordbox's controls.
   - **Screen Recording** or **Screen & System Audio Recording** — reads the track table. The name varies by macOS version; the watcher does not record audio.
7. Quit and reopen the watcher if macOS requests it. Updates can require enabling these permissions again because the app is ad hoc signed.

Updating preserves saved watcher progress. Your Apple Music account and subscription must already work inside Rekordbox.

## Analyze a playlist

1. Open **Apple Music → Library → Playlists** in Rekordbox and select a playlist. Open an actual playlist, not Apple Music search results or the Collection overview.
2. Keep the track number, **Track Title**, **Artist**, **Key** and **BPM** columns visible. The current reader expects the usual layout with Key before BPM. Widen columns if titles or values are unreadable.
3. Click **Analyze playlist** in the floating widget, or **Start analysis of open playlist** in the BPM menu.
4. During the countdown and selection/verification stages, keep Rekordbox visible and the Mac unlocked. Clicks, scrolling and keyboard input pause active UI automation; ordinary mouse movement does not.
5. Once tracks are queued, the widget shows **tracks remaining** from Rekordbox. You may use Rekordbox during this passive wait. Native analysis continues if the watcher is paused.
6. Return to the same playlist for the final check. Completion means **every row verified**, positive BPM, a present key and zero errors. The BPM menu shows **✓**, and the widget shows the completed count.

Analysis takes time, particularly for streaming tracks. Queue progress and final verification are separate stages. A submitted command or an empty queue alone is not proof that every row is filled.

### Controls and recovery

- **Pause / Analyze playlist:** pause the current run or analyze the currently open playlist.
- **Minimize:** hide the widget. **Close:** pause the watcher and hide it. **Show floating widget** in the BPM menu brings it back.
- **Details…:** inspect per-track results and errors; opening it during a scan pauses UI control.
- **Check playlist:** inspect fields without starting new analysis.
- **Resume saved playlist:** reopen the saved playlist in Rekordbox first, then resume. Cached results are rechecked.
- **Retry failed / Retry selected:** retry only the selected unresolved work. A failed stream is reported; the app does not retry forever.

Progress is stored locally in `~/Library/Application Support/Rekordbox BPM Key Watcher/`. Nothing starts automatically on launch or on a timer in the normal app.

### Multiple playlists (experimental)

Expand **Apple Music → Library → Playlists**, then choose **Analyze all Apple Music playlists** from the BPM menu. This changes the visible playlist as it works. **Resume saved library session** continues its queue, and **Library progress / skipped playlists…** shows results.

Only discoverable sidebar playlists are covered. Collapsed folders, unreadable or duplicate labels can prevent coverage. Full-library mode has not received the same live validation as the single-playlist workflow.

## How it works

The watcher reads Rekordbox's interface with macOS Accessibility and screen text recognition. It groups contiguous unfinished tracks with matching missing fields, submits batches of up to 32, splits selections Rekordbox rejects, and waits for Rekordbox's own analysis. Completed rows are checked against a second capture. Existing complete tracks are skipped.

Normal analysis uses Rekordbox's **Analyze Track / Analyze Key** commands without repeatedly opening Preferences. The watcher reads a small whitelist of saved analysis-option flags; it never edits that settings file. Key-only work uses Analyze Key. If the saved options would also change an existing key, cues, phrase or vocal data, the watcher reports the incompatibility instead of proceeding.

An interrupted settings recovery from an older version may open Preferences once to restore that earlier state. New runs do not create these recovery records.

There are **no direct Rekordbox database writes, Apple Music audio extraction, uploads or account credentials collected by the watcher**. It still controls the visible interface while selecting and verifying tracks. There is no verified invisible background integration.

## Known limits and test status

- Unavailable streams, account mismatches and analysis locks must be resolved in Rekordbox. The watcher cannot guarantee every track will work.
- OCR, column order, language, scaling and Rekordbox updates can affect recognition. An uncertain row is skipped or reported. A “present” key may be detected without a reliable transcription of its exact label; the saved data is not an authoritative metadata export.
- Saved Rekordbox options may lag unsaved changes in its Preferences. Check important results inside Rekordbox before a set.
- The tool attempts to restore the original playlist view after a normal finish. Exact pixel scroll, offscreen selections and the previous sort order are not guaranteed to be restored.
- Development testing on Apple silicon with Rekordbox **7.2.18** completed one **156-track playlist**: 93 newly analyzed in the final run, 63 already complete, zero run errors. The user subsequently confirmed that playlist worked.
- A second 31-track queue finished, but its final verification was interrupted by a view change. The newest page-at-a-time verification refinement has passed build and core tests; a complete live pass of that refinement remains unverified.
- The universal binary includes Intel code; Intel runtime behavior and every supported macOS version have not been physically tested. This remains a beta.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| App cannot launch | Read the first-launch instructions above; confirm macOS 14 or newer. |
| Permission warning after updating | Grant both permissions to the copy in Applications and restart it. Remove obsolete entries if macOS shows duplicate copies. |
| No widget | Activate Rekordbox and choose **Show floating widget** from the BPM menu. |
| Paused while selecting tracks | Finish the interaction, return to the intended playlist, then resume. |
| Queue finished but run is incomplete | Reopen the same playlist so the watcher can verify its columns; inspect Details for errors. |
| Import stays at 0% | Confirm the track is playable under the current Apple Music account. Stalled imports are reported rather than treated as complete. |
| Analysis options incompatible | Read the specific error. Configure only the needed analysis fields in Rekordbox yourself, then retry; the watcher will not silently overwrite existing data. |

## Build from source

Install Apple's Xcode Command Line Tools with a Swift compiler. Development used Swift 6.2+, compiling in Swift 5 language mode.

```sh
git clone https://github.com/andex23/rekordbox-bpm-key-watcher.git
cd rekordbox-bpm-key-watcher
./build.sh                         # Current Mac architecture, output in dist/
ARCHS="arm64 x86_64" ./build.sh     # Universal macOS 14+ app
./release.sh                      # Universal ZIP, README, license and checksums
```

Run the tests:

```sh
swiftc -swift-version 5 Core.swift Tests/CoreTests.swift -o /tmp/watcher-core-tests
/tmp/watcher-core-tests
swiftc -swift-version 5 Session.swift Tests/SessionTests.swift -o /tmp/watcher-session-tests
/tmp/watcher-session-tests
swiftc -swift-version 5 Core.swift NativeAnalysis.swift Tests/NativeAnalysisTests.swift -o /tmp/watcher-native-tests
/tmp/watcher-native-tests
```

Release ZIPs include this README and the license. `SHA256SUMS.txt` on the release page allows the ZIP's integrity to be checked with `shasum -a 256`.

## Contributing and license

Issues and pull requests are welcome. For a bug report, include your macOS and Rekordbox versions, Mac architecture, the watcher error, and whether the track works manually in Rekordbox. Redact personal information from screenshots and logs.

[MIT License](LICENSE). Unofficial community software; not affiliated with AlphaTheta, Pioneer DJ, Apple or Rekordbox.
