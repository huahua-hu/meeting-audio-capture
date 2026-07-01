# macOS 13 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Apple Silicon MeetingAudioCapture DMG that runs on macOS 13+ while retaining the native ScreenCaptureKit microphone path on macOS 15+.

**Architecture:** Lower the deployment target and replace Observation with Combine-compatible SwiftUI ownership. Route microphone capture by OS capability: ScreenCaptureKit on macOS 15+, `AVCaptureSession` on macOS 13/14, with both paths emitting the existing timestamped `CMSampleBuffer` events.

**Tech Stack:** Swift 6, SwiftUI, Combine, ScreenCaptureKit, AVFoundation, XCTest, macOS 13+

## Global Constraints

- Apple Silicon (`arm64`) only.
- Minimum deployment target is macOS 13.0.
- macOS 15 keeps ScreenCaptureKit microphone capture.
- macOS 13/14 uses `AVCaptureSession` microphone capture.
- Output remains one stereo M4A with system audio left and microphone right.
- Do not merge to `main` or publish before real macOS 13 validation.

---

### Task 1: macOS 13 SwiftUI and deployment compatibility

**Files:**
- Modify: `Package.swift`
- Modify: `Config/Info.plist`
- Modify: `Sources/MeetingAudioCapture/AppModel.swift`
- Modify: `Sources/MeetingAudioCapture/MeetingAudioCaptureApp.swift`
- Modify: `Sources/MeetingAudioCapture/Views/RecorderMenuView.swift`
- Test: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- Produces: `AppModel: ObservableObject` with `@Published` UI state.
- Produces: package and bundle deployment floor `13.0`.

- [ ] Add a failing bundle test asserting `LSMinimumSystemVersion == "13.0"`.
- [ ] Run the focused test and confirm it fails against `15.0`.
- [ ] Change Package.swift and Info.plist to macOS 13.
- [ ] Replace Observation ownership with `ObservableObject`, `@Published`, `@StateObject`, and `@ObservedObject`.
- [ ] Run `swift test` and resolve only compatibility compiler errors from this task.
- [ ] Commit with `feat: lower deployment target to macOS 13`.

### Task 2: Permission and capture strategy selection

**Files:**
- Create: `Sources/MeetingAudioCapture/Capture/MicrophonePermissionProvider.swift`
- Create: `Sources/MeetingAudioCapture/Capture/CaptureCapabilities.swift`
- Create: `Tests/MeetingAudioCaptureTests/CaptureCapabilitiesTests.swift`
- Modify: `Sources/MeetingAudioCapture/Capture/ScreenCaptureClient.swift`

**Interfaces:**
- Produces: `MicrophonePermissionProviding.requestPermission() async -> Bool`.
- Produces: `CaptureCapabilities.microphoneStrategy(for:) -> MicrophoneCaptureStrategy`.

- [ ] Write failing tests asserting macOS 13/14 select `.avCaptureSession` and macOS 15+ selects `.screenCaptureKit`.
- [ ] Run focused tests and confirm missing-type failure.
- [ ] Implement the strategy mapper and an `AVCaptureDevice` permission provider.
- [ ] Inject the permission provider into `ScreenCaptureClient` and remove `AVAudioApplication`.
- [ ] Run focused and full tests.
- [ ] Commit with `feat: select compatible microphone capture strategy`.

### Task 3: Legacy microphone capture and ScreenCaptureKit integration

**Files:**
- Create: `Sources/MeetingAudioCapture/Capture/LegacyMicrophoneCapture.swift`
- Create: `Tests/MeetingAudioCaptureTests/LegacyMicrophoneCaptureTests.swift`
- Modify: `Sources/MeetingAudioCapture/Capture/ScreenCaptureClient.swift`

**Interfaces:**
- Produces: `LegacyMicrophoneCapture.start(deviceID:) async throws`, `stop() async`, and a sample callback.
- Produces: `LegacyMicrophoneCapture.resolveDeviceID(requested:availableIDs:defaultID:)`.

- [ ] Write failing device-resolution tests for selected, missing, and default microphone IDs.
- [ ] Implement `LegacyMicrophoneCapture` with `AVCaptureSession`, `AVCaptureDeviceInput`, and `AVCaptureAudioDataOutput` on a serial queue.
- [ ] Guard every macOS 15 ScreenCaptureKit microphone API with `#available(macOS 15.0, *)`.
- [ ] Start/stop the legacy microphone alongside ScreenCaptureKit system audio on macOS 13/14; route samples through existing `.microphone` events.
- [ ] Verify pause/resume drops both sources through the existing `acceptsSamples` gate and setup failure stops both pipelines.
- [ ] Run focused and full tests.
- [ ] Commit with `feat: capture microphone on macOS 13 and 14`.

### Task 4: Apple Silicon macOS 13 artifact

**Files:**
- Modify: `Makefile`
- Test: `Tests/MeetingAudioCaptureTests/BundleConfigurationTests.swift`

**Interfaces:**
- Produces: `make dmg-macos13`.
- Produces: `.build/MeetingAudioCapture-0.1.0-macos13-arm64.dmg`.

- [ ] Add a build target using `--triple arm64-apple-macosx13.0` and the macOS 13 bundle metadata.
- [ ] Run `swift test`.
- [ ] Run `make dmg-macos13` and verify the app code signature and DMG checksum.
- [ ] Run `vtool -show-build` on the packaged executable and confirm `minos 13.0` and `arm64` with `lipo -archs`.
- [ ] Mount the DMG read-only and verify its app Info.plist declares `13.0`.
- [ ] Commit with `build: add macOS 13 Apple Silicon package`.
- [ ] Leave `compat/macos-13` and its worktree intact for real-device feedback.
