# Stereo M4A Output and Visible Menu Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three-track MP4 with one 48 kHz stereo M4A whose left channel is system audio and right channel is microphone audio, and make recording/pause badges visible in the menu bar.

**Architecture:** `RecordingFiles` will expose only two source CAF files and one temporary/final M4A. `RecordingExporter` will read aligned PCM sources in bounded chunks, downmix system stereo into the left channel, copy microphone mono into the right channel, and encode AAC directly with `AVAudioFile`. The menu label will reserve horizontal layout space for its gray dot or pause mark instead of offsetting overlays outside its bounds.

**Tech Stack:** Swift 6, AVFoundation/AVFAudio, SwiftUI, XCTest, macOS 15+

## Global Constraints

- Output `Meeting-YYYYMMDD-HHmmss.m4a`, AAC, 48 kHz, stereo, target 192 kbps.
- Left = `0.5 * systemLeft + 0.5 * systemRight`; right = microphone mono.
- Pad the shorter source with silence; clamp samples to `-1...1`.
- Keep temporary files in the application-owned system temporary directory and remove them only after successful final move.
- Add no third-party dependencies and retain the app icon/DMG packaging.
- Menu status badges remain gray, non-animated, and inside measured layout bounds.

---

### Task 1: M4A File Contract

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingFiles.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingFilesTests.swift`

- [ ] Write failing tests expecting `temporary.m4a`, `.m4a` collision-safe output names, and no MP4/intermediate M4A fields.
- [ ] Run `swift test --filter RecordingFilesTests` and verify the `.mp4` expectation fails.
- [ ] Replace MP4/intermediate paths with `temporaryM4A`; make `nextOutputURL()` return `.m4a`.
- [ ] Run focused tests and commit with `refactor: define single M4A recording output`.

### Task 2: Stereo Channel Encoder

**Files:**
- Create: `Sources/MeetingAudioCapture/Recording/StereoM4AEncoder.swift`
- Create: `Tests/MeetingAudioCaptureTests/StereoM4AEncoderTests.swift`

**Interface:**

```swift
struct StereoM4AEncoder: Sendable {
    func encode(systemCAF: URL, microphoneCAF: URL, destination: URL) throws
}
```

- [ ] Write a failing test with one-second sine fixtures: system left/right at 440 Hz and microphone at 880 Hz. Decode the M4A and assert two channels, 48 kHz, strong 440 Hz only on the left and strong 880 Hz only on the right.
- [ ] Add a failing unequal-duration test asserting the shorter microphone channel is silent after its source ends.
- [ ] Implement chunked 4,096-frame reading with `AVAudioFile`, equal system averaging, microphone copy, silence padding, clamping, and direct AAC settings (`kAudioFormatMPEG4AAC`, 48 kHz, two channels, 192000 bit/s).
- [ ] Run focused tests and commit with `feat: encode system and microphone as stereo M4A`.

### Task 3: Export Lifecycle Migration

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingExporter.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingExporterTests.swift`

- [ ] Replace MP4 tests with failing assertions for one `.m4a`, one stereo track, source-channel separation, success cleanup, failure retention, and cleanup-failure output preservation.
- [ ] Run `swift test --filter RecordingExporterTests` and verify failure against the MP4 exporter.
- [ ] Reduce `RecordingExporter` to invoke `StereoM4AEncoder`, validate one stereo 48 kHz track, move the M4A, and preserve existing cleanup semantics.
- [ ] Run focused and full tests; commit with `refactor: export one stereo M4A recording`.

### Task 4: In-Bounds Menu Bar Badges

**Files:**
- Modify: `Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingPresentationTests.swift`

- [ ] Confirm existing state-mapping tests cover dot and pause states.
- [ ] Replace the offset `ZStack` with a compact `HStack(spacing: 2)` containing the waveform and an in-bounds 5-point circle or 6-point pause symbol; use no offsets or red styling.
- [ ] Run `swift test --filter RecordingPresentationTests` and manually verify recording and paused states in the installed app.
- [ ] Commit with `fix: keep menu status badges inside layout bounds`.

### Task 5: Documentation, App, and DMG Verification

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] Replace three-track MP4 documentation with the stereo M4A left/right mapping and splitting note.
- [ ] Run `make clean && make test && make app && make dmg`.
- [ ] Verify the app signature, DMG CRC, and mounted app signature; manually record and inspect one generated M4A.
- [ ] Commit documentation with `docs: describe stereo M4A recording output`.
