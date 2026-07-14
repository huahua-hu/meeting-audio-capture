# Realtime Transcription Reconnect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconnect each XFYun realtime transcription stream after transient failures and silently stop one track after ten consecutive failed attempts.

**Architecture:** Extract retry accounting into a small value type, then keep one long-lived audio iterator per track while creating replaceable WebSocket connections. A successful `started` event resets the counter; failed setup, receive, and send operations trigger a one-second retry without affecting recording.

**Tech Stack:** Swift 6, Foundation `URLSessionWebSocketTask`, Swift concurrency, XCTest

## Global Constraints

- System and microphone tracks retry independently.
- Retry delay is exactly one second.
- Stop after exactly ten consecutive failures.
- Reset consecutive failures only after a server `started` event.
- Do not add user-facing warnings.
- Do not allow transcription failures to fail audio recording.

---

### Task 1: Retry policy

**Files:**
- Create: `Sources/MeetingAudioCapture/Realtime/XFYunReconnectPolicy.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunReconnectPolicyTests.swift`

**Interfaces:**
- Produces: `XFYunReconnectPolicy.registerFailure() -> XFYunReconnectDecision`
- Produces: `XFYunReconnectPolicy.registerStarted()`

- [ ] Write tests asserting failures one through nine return `.retry(after: .seconds(1))` and failure ten returns `.giveUp`.
- [ ] Run `swift test --filter XFYunReconnectPolicyTests` and confirm the missing types fail compilation.
- [ ] Implement the value type with a default limit of ten and a one-second delay.
- [ ] Run the focused tests and confirm they pass.
- [ ] Add a reset test, confirm it fails, then implement `registerStarted()` and rerun.

### Task 2: Reconnecting track worker

**Files:**
- Modify: `Sources/MeetingAudioCapture/Realtime/XFYunRealtimeTranscriber.swift`
- Create: `Tests/MeetingAudioCaptureTests/XFYunRealtimeTranscriberTests.swift`

**Interfaces:**
- Consumes: `XFYunReconnectPolicy`
- Produces: one independent reconnecting task for each `CaptureTrack`

- [ ] Introduce narrow WebSocket connection and sleeper dependencies in the test target, and write a test where the first connection fails before `started`, the second starts, and the pending chunk is sent once.
- [ ] Run `swift test --filter XFYunRealtimeTranscriberTests` and verify the test fails because the worker exits after the first error.
- [ ] Move the stream iterator outside the connection attempt loop, retain the unsent chunk, and apply `XFYunReconnectPolicy` after each failed attempt.
- [ ] Require and parse the initial `started` event before resetting failures or entering the send loop.
- [ ] Make the receiver cancel the current socket on receive errors or XFYun `.failed` events so the sender enters the retry loop.
- [ ] Increase each `AsyncStream` buffer from 512 to 2,048 chunks.
- [ ] Run the focused tests and confirm reconnect, threshold, reset, and pending-data behavior pass.

### Task 3: Verification and deployment

**Files:**
- Modify only if tests expose a defect in files already listed above.

- [ ] Run `swift test --disable-sandbox --build-path /private/tmp/mac-audio-reconnect-final` and require all tests to pass.
- [ ] Build the application using the repository release build script.
- [ ] Replace `/Applications/MeetingAudioCapture.app` while preserving the existing Keychain credentials.
- [ ] Run a short live recording after forcing one failed connection attempt, restore connectivity, and verify the diagnostics contain a non-empty `transcript.jsonl` and the exported Markdown exists.
- [ ] Confirm the source contains no embedded XFYun key values and report the final commit and installed version.

