# Existing M4A Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible picker that transcribes existing stereo M4A exports without preserved diagnostics.

**Architecture:** Model a transcription session as either preserved tracks or a stereo export. A focused audio preprocessor extracts left/right channels into bounded-duration temporary files; the service recognizes each chunk with timestamp offsets and always cleans up temporary artifacts.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFAudio, Speech, XCTest.

## Global Constraints

- Support MeetingAudioCapture stereo M4A exports only.
- Left channel is Interviewer; right channel is Me.
- Do not modify the selected recording.
- Do not load the full recording into memory.
- Remove temporary files after success or failure.
- Keep existing diagnostics-based transcription working.
- Preserve the unrelated `Scripts/create-dmg.sh` worktree change.

---

### Task 1: Resolve Existing Stereo Exports

**Files:**
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionSession.swift`
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionModels.swift`
- Test: `Tests/MeetingAudioCaptureTests/TranscriptionSessionTests.swift`

**Interfaces:**
- Produces: `enum TranscriptionTrackSource`
- Produces: `static func TranscriptionSession.resolveSelectedAudio(outputFile:) throws`

- [ ] Add tests proving diagnostics are preferred and a readable two-channel M4A resolves as `.stereoExport`.
- [ ] Run `swift test --filter TranscriptionSessionTests` and confirm the new test fails because the API is absent.
- [ ] Validate the extension and channel count with `AVAudioFile`; return localized errors for unsupported files.
- [ ] Run the focused tests and commit `feat: resolve stereo transcription exports`.

### Task 2: Extract Bounded Stereo Chunks

**Files:**
- Create: `Sources/MeetingAudioCapture/Transcription/StereoChannelExtractor.swift`
- Create: `Tests/MeetingAudioCaptureTests/StereoChannelExtractorTests.swift`

**Interfaces:**
- Produces: `struct ExtractedAudioChunk` with `startTime`, `systemAudioFile`, and `microphoneAudioFile`.
- Produces: `StereoChannelExtractor.extract(url:chunkDuration:) throws -> ExtractedAudioTracks`.
- Produces: `ExtractedAudioTracks.cleanup()`.

- [ ] Write a stereo fixture test whose left and right channels contain different tones and whose duration creates multiple chunks.
- [ ] Run `swift test --filter StereoChannelExtractorTests` and confirm failure because the extractor is absent.
- [ ] Stream `AVAudioFile` buffers into temporary mono CAF chunk files, rolling files at the configured frame count.
- [ ] Assert channel mapping, offsets, chunk count, and cleanup; run focused tests.
- [ ] Commit `feat: extract stereo transcription chunks`.

### Task 3: Recognize Chunks with Offsets

**Files:**
- Modify: `Sources/MeetingAudioCapture/Transcription/TranscriptionService.swift`
- Modify: `Tests/MeetingAudioCaptureTests/TranscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `TranscriptionTrackSource`, `StereoChannelExtractor`.
- Produces: recognition results offset by each chunk's `startTime`.

- [ ] Add a fake recognizer test proving segments from later chunks receive the correct absolute timestamp.
- [ ] Run the focused test and confirm it fails against single-file recognition.
- [ ] Prepare diagnostics as one chunk and stereo exports through the extractor; recognize both speakers per chunk and merge results.
- [ ] Use `defer` cleanup for extracted tracks on every exit path.
- [ ] Run all transcription service tests and commit `feat: transcribe stereo audio chunks`.

### Task 4: Add the Persistent Picker Entry

**Files:**
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Modify: `Sources/MeetingAudioCapture/Localization/AppLocalization.swift`
- Modify: `Tests/MeetingAudioCaptureTests/AppLocalizationTests.swift`

**Interfaces:**
- Produces: `AppModel.selectAudioForTranscription()`.
- Produces localized key: `selectAudioAndTranscribe`.

- [ ] Add English and Chinese localization assertions and confirm they fail.
- [ ] Add the localized strings and a file picker restricted to `UTType.mpeg4Audio`.
- [ ] Resolve the selected file and show the existing transcription window, reporting validation errors through `displayError`.
- [ ] Add an always-visible icon-label button below the recording controls.
- [ ] Run localization tests and `swift build`; commit `feat: select existing audio for transcription`.

### Task 5: Verify and Deploy

**Files:**
- No production source changes unless verification finds a defect.

- [ ] Run `swift test --disable-sandbox` and require zero failures.
- [ ] Run `make app` and verify the generated signature.
- [ ] Verify the supplied 66-minute M4A resolves and preprocesses at least its first chunk without modifying the source.
- [ ] Replace `/Applications/MeetingAudioCapture.app`, launch it, and verify the installed binary and Speech usage description.
- [ ] Confirm `git status` contains only the pre-existing `Scripts/create-dmg.sh` change.
