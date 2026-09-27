# Changelog

## v0.1.0-beta.5 — 2026-09-27

- Floating widget with minimize/close controls and a prominent native queue count.
- Analyze the currently open playlist; skip complete tracks.
- Queue matching unfinished tracks in groups of up to 32, retry and split rejected groups.
- Allow normal interaction during the passive native-analysis wait.
- Use native analysis commands without repeated Preferences changes.
- Improve playlist detection, row-number recognition and clipped-row handling.
- Verify completed rows by page against a second capture.
- Report incomplete runs accurately and retain saved progress/retry controls.
- Universal Apple silicon/Intel download with installation guide, MIT license and checksum.

Validation: core, session and native-option tests pass. During development one
156-track playlist completed with zero run errors. Later OCR/reporting and
page-verification refinements have not completed a fresh full live pass. Intel
runtime and full-library coverage remain unverified. This is an experimental,
ad hoc signed, non-notarized release; see README for requirements and limits.
