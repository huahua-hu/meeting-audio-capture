# Audio Diagnostics and Track Leveling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve lossless per-track diagnostics and export a peak-safe stereo M4A whose system and microphone tracks have balanced constant loudness.

**Architecture:** Instrument `PCMTrackWriter` and `RecordingCoordinator` to produce a Codable timeline report beside the temporary CAF files. Add a focused two-pass audio analyzer used by `StereoM4AEncoder`, then make `RecordingExporter` preserve CAF/JSON artifacts under the output directory and prune old diagnostic sessions.

**Tech Stack:** Swift 6, AVFAudio, AVFoundation, Foundation, XCTest, macOS 13+

## Global Constraints

- Keep system audio on the left channel and microphone audio on the right channel.
- Use one constant gain per track; do not add compression, AGC, denoising, de-clicking, or crossfades.
- Target -24 dBFS gated RMS, cap boost at +12 dB, and reserve a -3 dBFS sample-peak ceiling.
- Preserve `system.caf`, `microphone.caf`, and `timeline.json` under `<output>/.diagnostics/<recording stem>/`.
- Retain only the five newest application-owned diagnostic directories.
- Do not modify or discard the existing unstaged `Scripts/create-dmg.sh` mode change.

---

### Task 1: Report Timeline Alignment Decisions

**Files:**
- Create: `Sources/MeetingAudioCapture/Recording/RecordingDiagnostics.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/PCMTrackWriter.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingCoordinator.swift`
- Test: `Tests/MeetingAudioCaptureTests/PCMTrackWriterTests.swift`
- Create: `Tests/MeetingAudioCaptureTests/RecordingDiagnosticsTests.swift`

**Interfaces:**
- Produces: `TrackAppendResult(insertedSilenceFrames:discardedOverlapFrames:)`.
- Produces: `TrackTimelineDiagnostics.record(bufferPTS:appendResult:)` and `RecordingTimelineDiagnostics` Codable output.

- [ ] **Step 1: Add failing append-result tests**

Add assertions that a 4,800-frame gap returns `insertedSilenceFrames == 4_800`, an overlapping append returns the exact discarded count, and tolerated jitter reports zeros.

```swift
let result = try writer.append(second, atFrame: 9_600)
XCTAssertEqual(result.insertedSilenceFrames, 4_800)
XCTAssertEqual(result.discardedOverlapFrames, 0)
```

- [ ] **Step 2: Verify the focused tests fail**

Run: `swift test --filter PCMTrackWriterTests`

Expected: compilation fails because `append` returns `Void`.

- [ ] **Step 3: Return alignment outcomes from the writer**

Add:

```swift
struct TrackAppendResult: Equatable, Sendable {
    let insertedSilenceFrames: AVAudioFramePosition
    let discardedOverlapFrames: AVAudioFramePosition
}
```

Mark `append` with `@discardableResult`, return exact inserted and discarded frame counts, and return the full overlap count when an incoming buffer is completely discarded.

- [ ] **Step 4: Verify writer tests pass**

Run: `swift test --filter PCMTrackWriterTests`

Expected: all focused tests pass.

- [ ] **Step 5: Add failing Codable diagnostics tests**

Test that recording two append results accumulates buffer count, silence, overlap, maximum absolute gap, and event timestamps, then round-trips through `JSONEncoder` and `JSONDecoder`.

```swift
var track = TrackTimelineDiagnostics()
track.record(bufferPTSSeconds: 1.5, expectedFrame: 4_800, appendResult: .init(insertedSilenceFrames: 240, discardedOverlapFrames: 0))
XCTAssertEqual(track.receivedBufferCount, 1)
XCTAssertEqual(track.insertedSilenceFrames, 240)
```

- [ ] **Step 6: Implement diagnostics models and coordinator collection**

Define Codable, Equatable, Sendable `TimelineAnomaly`, `TrackTimelineDiagnostics`, and `RecordingTimelineDiagnostics`. In `RecordingCoordinator.write`, capture the writer result for the selected track and update the corresponding diagnostic state using PTS seconds and target frame. Before export, encode the report to `files.timelineDiagnosticsJSON` using sorted, pretty-printed JSON.

- [ ] **Step 7: Run focused and full tests**

Run: `swift test --filter RecordingDiagnosticsTests && swift test`

Expected: all tests pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingDiagnostics.swift Sources/MeetingAudioCapture/Recording/PCMTrackWriter.swift Sources/MeetingAudioCapture/Recording/RecordingCoordinator.swift Tests/MeetingAudioCaptureTests/PCMTrackWriterTests.swift Tests/MeetingAudioCaptureTests/RecordingDiagnosticsTests.swift
git commit -m "feat: record audio timeline diagnostics"
```

### Task 2: Calculate Peak-Safe Constant Track Gains

**Files:**
- Create: `Sources/MeetingAudioCapture/Recording/AudioTrackLeveler.swift`
- Create: `Tests/MeetingAudioCaptureTests/AudioTrackLevelerTests.swift`

**Interfaces:**
- Produces: `AudioTrackLeveler.measure(samples:) -> AudioTrackMeasurement`.
- Produces: `AudioTrackLeveler.gain(for:) -> Float` using target RMS `10^(-24/20)`, activity gate `10^(-50/20)`, maximum gain `10^(12/20)`, and peak ceiling `10^(-3/20)`.

- [ ] **Step 1: Add failing measurement and gain tests**

Cover silence, a constant 0.1 signal, samples below the -50 dBFS gate, +12 dB maximum boost, and peak-limited gain.

```swift
let measurement = AudioTrackLeveler.measure(samples: [0.1, -0.1, 0, 0])
XCTAssertEqual(measurement.peak, 0.1, accuracy: 0.0001)
XCTAssertEqual(measurement.gatedRMS, 0.1, accuracy: 0.0001)
XCTAssertLessThanOrEqual(AudioTrackLeveler.gain(for: peakHeavyMeasurement) * peakHeavyMeasurement.peak, pow(10, -3.0 / 20.0) + 0.0001)
```

- [ ] **Step 2: Verify tests fail for the missing type**

Run: `swift test --filter AudioTrackLevelerTests`

Expected: compilation fails with `cannot find AudioTrackLeveler in scope`.

- [ ] **Step 3: Implement the pure analyzer**

Accumulate finite active samples whose absolute amplitude is at least the gate, compute gated RMS from their squared sum, and track absolute peak across all finite samples. Return unity gain for silence. Calculate `min(targetRMSGain, maximumBoost, peakCeilingGain)` and reject non-finite input with `AudioTrackLevelingError.nonFiniteSample`.

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter AudioTrackLevelerTests`

Expected: all focused tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/MeetingAudioCapture/Recording/AudioTrackLeveler.swift Tests/MeetingAudioCaptureTests/AudioTrackLevelerTests.swift
git commit -m "feat: calculate peak-safe track gains"
```

### Task 3: Apply Two-Pass Leveling During Stereo Export

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/AudioTrackLeveler.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/StereoM4AEncoder.swift`
- Modify: `Tests/MeetingAudioCaptureTests/StereoM4AEncoderTests.swift`

**Interfaces:**
- Consumes: `AudioTrackLeveler.measure(samples:)` and `gain(for:)` from Task 2.
- Produces: two-pass `StereoM4AEncoder.encode(systemCAF:microphoneCAF:destination:)` with constant per-track gain.

- [ ] **Step 1: Add failing encoder-level tests**

Create unequal fixtures and assert decoded left/right RMS values are within 1 dB while neither decoded channel exceeds approximately -2.5 dBFS after AAC overshoot allowance. Retain the frequency-isolation and shorter-track padding assertions.

```swift
let leftRMS = rms(left, range: 0..<count)
let rightRMS = rms(right, range: 0..<count)
XCTAssertEqual(20 * log10(leftRMS / rightRMS), 0, accuracy: 1.0)
XCTAssertLessThan(maxAbs(left, count: count), 0.76)
XCTAssertLessThan(maxAbs(right, count: count), 0.76)
```

- [ ] **Step 2: Verify the new test fails against the current encoder**

Run: `swift test --filter StereoM4AEncoderTests`

Expected: the unequal fixture remains unbalanced or violates the peak assertion.

- [ ] **Step 3: Add streaming CAF measurement**

Add an analyzer method that reads `AVAudioFile` in 4,096-frame chunks. For the stereo system CAF, measure the same `0.5 * left + 0.5 * right` downmix used during output. Rewind both files to frame zero after measurement.

- [ ] **Step 4: Apply constant gains in the encoder**

Calculate system and microphone gain before creating the M4A, multiply samples during the existing output loop, and retain the final `[-1, 1]` safety clamp. Do not introduce any per-buffer gain changes.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter StereoM4AEncoderTests && swift test`

Expected: all tests pass and channel mapping remains unchanged.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/MeetingAudioCapture/Recording/AudioTrackLeveler.swift Sources/MeetingAudioCapture/Recording/StereoM4AEncoder.swift Tests/MeetingAudioCaptureTests/StereoM4AEncoderTests.swift
git commit -m "feat: balance exported audio tracks"
```

### Task 4: Preserve and Prune Diagnostic Sessions

**Files:**
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingFiles.swift`
- Modify: `Sources/MeetingAudioCapture/Recording/RecordingExporter.swift`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingFilesTests.swift`
- Modify: `Tests/MeetingAudioCaptureTests/RecordingExporterTests.swift`

**Interfaces:**
- Consumes: `RecordingFiles.timelineDiagnosticsJSON` written by Task 1.
- Produces: `RecordingFiles.preserveDiagnostics(for:)` and `RecordingFiles.pruneDiagnostics(keeping:)`.

- [ ] **Step 1: Add failing path and retention tests**

Assert that a recording output named `Meeting-20260701-120000-2.m4a` maps to `.diagnostics/Meeting-20260701-120000-2/`, that preservation moves both CAF files and JSON, and that pruning removes the oldest of six timestamped directories while leaving unrelated files untouched.

- [ ] **Step 2: Verify RecordingFiles tests fail**

Run: `swift test --filter RecordingFilesTests`

Expected: compilation fails because diagnostic APIs are missing.

- [ ] **Step 3: Implement diagnostic paths, preservation, and pruning**

Add `timelineDiagnosticsJSON` to the session. `preserveDiagnostics(for:)` creates the hidden container and recording directory, then moves the two CAF files and JSON. `pruneDiagnostics(keeping: 5)` sorts only child directories by content modification date, removes entries beyond five, and never removes non-directory children.

- [ ] **Step 4: Run RecordingFiles tests**

Run: `swift test --filter RecordingFilesTests`

Expected: all focused tests pass.

- [ ] **Step 5: Add failing exporter integration tests**

Change success expectations from session deletion alone to a completed visible M4A plus three diagnostic artifacts. Add an injected preservation failure and assert the M4A remains while the temporary session remains recoverable. Keep encoding-failure assertions for no partial visible M4A.

- [ ] **Step 6: Integrate preservation into export and startup cleanup**

Choose `outputURL` once, encode and validate, move the M4A, then preserve diagnostics. Remove the now-empty temporary session only after preservation succeeds. On app startup, call `RecordingFiles.pruneDiagnostics(in: destination, keeping: 5)` after loading the saved destination.

- [ ] **Step 7: Run focused and full verification**

Run: `swift test --filter RecordingExporterTests && swift test && git diff --check`

Expected: all tests pass and diff check produces no output.

- [ ] **Step 8: Commit Task 4**

```bash
git add Sources/MeetingAudioCapture/Recording/RecordingFiles.swift Sources/MeetingAudioCapture/Recording/RecordingExporter.swift Sources/MeetingAudioCapture/AppModel.swift Tests/MeetingAudioCaptureTests/RecordingFilesTests.swift Tests/MeetingAudioCaptureTests/RecordingExporterTests.swift
git commit -m "feat: preserve recent audio diagnostics"
```

### Task 5: Final Artifact Verification

**Files:**
- Verify only; no planned source edits.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified macOS 13 arm64 build and DMG.

- [ ] **Step 1: Run the complete test suite from a clean build**

Run: `swift package clean && swift test`

Expected: all tests pass.

- [ ] **Step 2: Build the compatibility artifact**

Run: `make dmg-macos13`

Expected: `.build/MeetingAudioCapture-0.1.0-macos13-arm64.dmg` is created.

- [ ] **Step 3: Verify metadata and signature**

Mount the DMG read-only and run `vtool -show-build`, `lipo -archs`, `plutil -extract LSMinimumSystemVersion raw`, and `codesign --verify --deep --strict` against its app.

Expected: `minos 13.0`, `arm64`, plist value `13.0`, and valid signature.

- [ ] **Step 4: Record the real-device follow-up**

Report that the next real recording must compare `.diagnostics/<stem>/system.caf` against its M4A before any de-clicking or capture changes are considered.
