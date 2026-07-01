# macOS 13 Compatibility Design

## Goal

Produce an Apple Silicon build of MeetingAudioCapture that runs on macOS 13.0 or later while preserving the current macOS 15 capture path and output format. Development remains isolated on `compat/macos-13` until real macOS 13 runtime validation is complete.

## Compatibility Gaps

The current application requires macOS 15 because it uses ScreenCaptureKit microphone capture (`captureMicrophone`, `microphoneCaptureDeviceID`, and `SCStreamOutputType.microphone`). Those APIs are unavailable before macOS 15. It also uses macOS 14 APIs through Observation (`@Observable` and `@Bindable`) and `AVAudioApplication.requestRecordPermission()`.

ScreenCaptureKit system-audio capture (`capturesAudio`, sample rate, channel count, and current-process exclusion) is available on macOS 13 and remains suitable.

## Capture Architecture

`ScreenCaptureClient` remains the single `CaptureClient` exposed to the recording coordinator and chooses its microphone implementation at runtime:

- macOS 15 and later: keep ScreenCaptureKit system-audio and microphone outputs.
- macOS 13 and 14: capture system audio through ScreenCaptureKit and microphone audio through a new `LegacyMicrophoneCapture` backed by `AVCaptureSession` and `AVCaptureAudioDataOutput`.

`LegacyMicrophoneCapture` resolves the selected `AVCaptureDevice` by unique ID, falling back to the default audio device when no ID is selected. Its delegate forwards microphone `CMSampleBuffer` values into the same event stream used by ScreenCaptureKit. This preserves the coordinator, decoder, timeline, temporary CAF files, stereo M4A export, level meters, pause behavior, and cleanup flow.

Both ScreenCaptureKit and AVCapture timestamps use the host-time clock domain. The existing coordinator continues to select the earlier first presentation timestamp as the recording origin and pads any initial offset with silence. Pause and resume continue to discard incoming samples while retaining the shared timeline behavior.

Startup is atomic from the user's perspective: permission is checked first, both capture pipelines are configured, then capture begins. If either pipeline fails, both are stopped and the existing setup error is reported. Stop is idempotent and closes both pipelines.

## Permissions

Use `AVCaptureDevice.authorizationStatus(for: .audio)` and `AVCaptureDevice.requestAccess(for: .audio)` on every supported OS. Screen recording/system-audio permission remains managed by ScreenCaptureKit. Existing privacy usage descriptions remain in the app bundle.

## SwiftUI State Compatibility

Replace Observation with `ObservableObject` and mark UI-observed state with `@Published`. The app owns the model through `@StateObject`, and `RecorderMenuView` observes it through `@ObservedObject`. This API set is available on macOS 13 and preserves runtime language switching, microphone selection, levels, recording state, and errors.

## Deployment and Artifact

- Set the Swift package deployment floor to macOS 13.
- Set `LSMinimumSystemVersion` to `13.0`.
- Build Apple Silicon (`arm64`) with a macOS 13 deployment target using the installed macOS 15.5 SDK.
- Produce a separate artifact named `MeetingAudioCapture-0.1.0-macos13-arm64.dmg` so it cannot be confused with the currently published macOS 15 package.
- Keep the existing application name and bundle identifier; users should install only one build at a time.

## Testing and Validation

Automated tests will cover:

- Runtime selection of ScreenCaptureKit microphone capture on macOS 15 and legacy microphone capture on macOS 13/14.
- Permission-state behavior through an injected permission provider.
- Selected-device and default-device resolution for the legacy microphone pipeline.
- Existing coordinator, stereo M4A, localization, and indicator behavior.
- Successful compilation with `arm64-apple-macosx13.0` and verification that the binary and bundle declare macOS 13 as their minimum version.
- Code-signature and DMG checksum verification.

The current development machine runs macOS 15.5, so it cannot prove runtime behavior on macOS 13. Before publishing this artifact as supported, the colleague must test permission prompts, system-audio capture, microphone capture, pause/resume, and left/right playback on a real Apple Silicon Mac running macOS 13.

## Scope

This work does not add Intel support, change the M4A channel layout, change the interface design, notarize the app, or replace the existing v0.1.0 Release before real macOS 13 validation.
