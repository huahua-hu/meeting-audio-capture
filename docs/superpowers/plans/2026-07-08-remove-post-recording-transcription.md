# Remove Post-Recording Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Apple Speech post-recording transcription and export real-time transcript turns with absolute system timestamps.

**Architecture:** Store the recording session's wall-clock start date in every real-time journal entry while retaining relative phrase time for sorting. Remove the isolated `Transcription` feature directory, its UI entry points, permission declaration, localization, and tests without changing recording diagnostics or XFYun real-time components.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, Swift Package Manager, macOS Keychain and URLSession WebSocket.

## Global Constraints

- Keep XFYun real-time dual-track transcription and Keychain credentials.
- Keep JSONL persistence, M4A export, Markdown export, and diagnostics.
- Do not commit or modify the user's `Scripts/create-dmg.sh` change.
- Do not push the branch.

---

### Task 1: Absolute Transcript Time

**Files:**
- Modify: `Sources/MeetingAudioCapture/Realtime/TranscriptJournal.swift`
- Modify: `Sources/MeetingAudioCapture/Realtime/XFYunRealtimeTranscriber.swift`
- Modify: `Tests/MeetingAudioCaptureTests/TranscriptJournalTests.swift`

**Interfaces:**
- `TranscriptJournalEntry` adds `sessionStartedAt: Date`.
- `XFYunRealtimeTranscriber.init` captures one `Date` and supplies it to both track entries.
- `renderMarkdown` sorts by relative `startTime` and displays `sessionStartedAt.addingTimeInterval(startTime)`.

- [ ] Write a test with a fixed session date and out-of-order two-track entries; assert `[2026-07-08 19:00:01]` ordering.
- [ ] Run `swift test --disable-sandbox --filter TranscriptJournalTests --build-path /private/tmp/mac-audio-build` and confirm the test fails because absolute time is absent.
- [ ] Add `sessionStartedAt`, calculate the absolute turn date, and format it using `yyyy-MM-dd HH:mm:ss` with an injectable/current time zone.
- [ ] Run the focused test and confirm it passes.

### Task 2: Remove Post-Recording Transcription

**Files:**
- Delete: `Sources/MeetingAudioCapture/Transcription/`
- Delete: `Sources/MeetingAudioCapture/Views/TranscriptionView.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Modify: `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`
- Modify: `Config/Info.plist`
- Delete: `Tests/MeetingAudioCaptureTests/StereoChannelExtractorTests.swift`
- Delete: `Tests/MeetingAudioCaptureTests/TranscriptFormatterTests.swift`
- Delete: `Tests/MeetingAudioCaptureTests/TranscriptSegmentAssemblerTests.swift`
- Delete: `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`
- Delete: `Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift`
- Delete: `Tests/MeetingAudioCaptureTests/TranscriptionViewModelTests.swift`
- Modify: `Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift`
- Modify: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- `AppModel` no longer exposes post-recording transcription state or actions.
- `RecorderMenuView` contains no post-recording transcription controls.
- `Info.plist` contains no Speech Recognition usage description.

- [ ] Update configuration/localization tests to assert post-recording strings, UI symbols, `import Speech`, and `NSSpeechRecognitionUsageDescription` are absent.
- [ ] Run focused tests and confirm they fail before production cleanup.
- [ ] Delete the feature files and remove all call sites, strings, and permission declarations.
- [ ] Run `rg -n 'TranscriptionWindowController|selectAudioForTranscription|openTranscriptionForLastRecording|import Speech|NSSpeechRecognitionUsageDescription' Sources Config` and require no matches.
- [ ] Run the complete Swift test suite and confirm zero failures.

### Task 3: Commit, Build, and Replace

**Files:**
- Build: `.build/MeetingAudioCapture.app`
- Replace: `/Applications/MeetingAudioCapture.app`

- [ ] Run `git diff --check` and verify only intended files plus the untouched user script appear.
- [ ] Commit the implementation locally with `fix: remove post-recording transcription`.
- [ ] Run `make app` and require a successful release build and code signing.
- [ ] Replace `/Applications/MeetingAudioCapture.app`, launch it, verify `codesign`, binary equality, and a running process.
- [ ] Run `git status --short` and confirm only `Scripts/create-dmg.sh` remains modified.
