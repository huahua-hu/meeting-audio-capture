# Follow System Default Microphone During Recording

## Problem

MeetingAudioCapture resolves the selected microphone only when recording starts. When the user selects System Default and macOS changes its default input device, such as after connecting Bluetooth headphones, the active capture session remains bound to the previous microphone. System audio continues, but microphone samples stop or continue from the wrong device.

## Required Behavior

- System Default follows changes to the macOS default input device while recording.
- Connecting or disconnecting headphones does not stop the recording or system-audio capture.
- A specifically selected microphone remains fixed and ignores default-input changes.
- Duplicate device notifications do not cause duplicate reconfiguration.
- Device monitoring stops with the capture session.
- A short microphone gap during reconfiguration remains a real gap on the existing recording timeline.
- No new page, button, or alert is added.

## Design

### Default Input Monitoring

Add a small CoreAudio-backed monitor that listens for changes to `kAudioHardwarePropertyDefaultInputDevice`. The callback resolves the current input through `AVCaptureDevice.default(for: .audio)` and emits its unique device ID. Monitoring starts only when the recording was started with a nil microphone ID, which represents System Default, and is removed during stop or failed startup.

The monitor exposes a narrow protocol so route behavior can be tested without changing real hardware.

### Route Coordination

Add a route coordinator that owns the current device ID and serializes updates. It ignores duplicate IDs and ignores all updates after stop. A new default device is applied through a backend-specific asynchronous callback. Failed updates are retried after a short delay while capture remains active; a later device notification supersedes an older pending route.

### macOS 15 And Later

Store the active `SCStreamConfiguration`. At startup, resolve System Default to an explicit current microphone ID. When the monitor reports a new default, copy the complete stream configuration, replace `microphoneCaptureDeviceID`, and call `SCStream.updateConfiguration(_:)`. System audio and the stream itself remain active.

### macOS 13 And 14

Keep ScreenCaptureKit system-audio capture running. Reconfigure only `LegacyMicrophoneCapture` on its private serial queue by stopping its current `AVCaptureSession` and starting a new session for the new default device.

### Timeline And Transcription

No changes are needed in `RecordingCoordinator`. Incoming microphone buffers retain their presentation timestamps. Existing `PCMTrackWriter` behavior inserts silence for the switch gap, and real-time transcription resumes when new microphone buffers arrive.

## Failure Handling

- Monitoring registration failure does not stop an already-started recording; the original microphone remains active.
- A route update failure is retried while the capture remains active.
- Stop cancels pending retries before stopping capture resources.
- Full stream errors continue through the existing `CaptureEvent.stopped` path.

## Testing

- System Default applies a newly reported device.
- An explicitly selected microphone ignores default-device changes.
- Repeated reports of the same device are applied once.
- Stop prevents subsequent updates and retries.
- A failed update retries and succeeds without ending capture.
- Existing capture, recording, transcription, credential, and export tests remain green.

