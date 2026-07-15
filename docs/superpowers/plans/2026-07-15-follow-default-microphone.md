# Follow Default Microphone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep microphone recording active when the macOS default input device changes during a recording started with System Default.

**Architecture:** A CoreAudio listener reports default-input changes through a testable monitor. An actor serializes route changes, suppresses duplicates, retries failures, and applies the new device through either ScreenCaptureKit configuration updates on macOS 15+ or a microphone-only AVCaptureSession replacement on macOS 13/14.

**Tech Stack:** Swift 6, CoreAudio, AVFoundation, ScreenCaptureKit, XCTest, Swift Package Manager.

## Global Constraints

- Support macOS 13 and later with no new dependency.
- System Default follows input-device changes; an explicitly selected microphone remains fixed.
- Keep system-audio capture, the recording session, and real-time transcription alive during a microphone switch.
- Preserve switch gaps as silence on the existing timeline.
- Add no page, button, or alert.
- Stop all monitoring and retry work when capture stops.

---

### Task 1: Default Microphone Route Controller

**Files:**
- Create: `Sources/MeetingAudioCapture/Capture/MicrophoneRouteController.swift`
- Create: `Tests/MeetingAudioCaptureTests/MicrophoneRouteControllerTests.swift`

**Interfaces:**
- Produces: `actor MicrophoneRouteController`
- Produces: `init(requestedDeviceID:initialDefaultDeviceID:retryDelay:applyDevice:)`
- Produces: `func defaultDeviceDidChange(to:) async` and `func stop()`

- [ ] **Step 1: Write failing route-policy tests**

Create tests covering default following, explicit-device pinning, duplicate suppression, retry, and stop:

```swift
@testable import MeetingAudioCapture
import XCTest

final class MicrophoneRouteControllerTests: XCTestCase {
    func testSystemDefaultAppliesNewDeviceOnce() async {
        let recorder = RouteApplyRecorder()
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { try await recorder.apply($0) }
        )

        await controller.defaultDeviceDidChange(to: "headset")
        await controller.defaultDeviceDidChange(to: "headset")

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, ["headset"])
    }

    func testExplicitDeviceIgnoresDefaultChanges() async {
        let recorder = RouteApplyRecorder()
        let controller = MicrophoneRouteController(
            requestedDeviceID: "usb-mic",
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { try await recorder.apply($0) }
        )

        await controller.defaultDeviceDidChange(to: "headset")

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, [])
    }

    func testFailedUpdateRetriesUntilItSucceeds() async {
        let recorder = RouteApplyRecorder(failuresRemaining: 1)
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { try await recorder.apply($0) }
        )

        await controller.defaultDeviceDidChange(to: "headset")

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, ["headset", "headset"])
    }

    func testStopIgnoresLaterChanges() async {
        let recorder = RouteApplyRecorder()
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { try await recorder.apply($0) }
        )

        await controller.stop()
        await controller.defaultDeviceDidChange(to: "headset")

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, [])
    }
}

private enum RouteApplyFailure: Error { case expected }

private actor RouteApplyRecorder {
    private var applied: [String] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func apply(_ deviceID: String) throws {
        applied.append(deviceID)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RouteApplyFailure.expected
        }
    }

    func deviceIDs() -> [String] { applied }
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
swift test --filter MicrophoneRouteControllerTests
```

Expected: compilation fails because `MicrophoneRouteController` does not exist.

- [ ] **Step 3: Implement the minimal route controller**

Create an actor with these semantics:

```swift
import Foundation

actor MicrophoneRouteController {
    typealias ApplyDevice = @Sendable (String) async throws -> Void
    typealias RetryDelay = @Sendable () async -> Void

    private let followsSystemDefault: Bool
    private let retryDelay: RetryDelay
    private let applyDevice: ApplyDevice
    private var activeDeviceID: String?
    private var targetDeviceID: String?
    private var generation = 0
    private var isStopped = false

    init(
        requestedDeviceID: String?,
        initialDefaultDeviceID: String?,
        retryDelay: @escaping RetryDelay = {
            try? await Task.sleep(nanoseconds: 500_000_000)
        },
        applyDevice: @escaping ApplyDevice
    ) {
        followsSystemDefault = requestedDeviceID == nil
        activeDeviceID = requestedDeviceID ?? initialDefaultDeviceID
        self.retryDelay = retryDelay
        self.applyDevice = applyDevice
    }

    func defaultDeviceDidChange(to deviceID: String?) async {
        guard followsSystemDefault,
              !isStopped,
              let deviceID,
              deviceID != activeDeviceID,
              deviceID != targetDeviceID else { return }

        targetDeviceID = deviceID
        generation += 1
        let updateGeneration = generation

        while !isStopped, generation == updateGeneration {
            do {
                try await applyDevice(deviceID)
                guard !isStopped, generation == updateGeneration else { return }
                activeDeviceID = deviceID
                targetDeviceID = nil
                return
            } catch {
                await retryDelay()
            }
        }
    }

    func stop() {
        isStopped = true
        generation += 1
        targetDeviceID = nil
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run `swift test --filter MicrophoneRouteControllerTests`.

Expected: 4 tests pass with 0 failures.

- [ ] **Step 5: Commit the route controller**

```bash
git add Sources/MeetingAudioCapture/Capture/MicrophoneRouteController.swift Tests/MeetingAudioCaptureTests/MicrophoneRouteControllerTests.swift
git commit -m "feat: coordinate default microphone changes"
```

---

### Task 2: CoreAudio Default Input Monitor

**Files:**
- Create: `Sources/MeetingAudioCapture/Capture/DefaultInputDeviceMonitor.swift`
- Create: `Tests/MeetingAudioCaptureTests/DefaultInputDeviceMonitorTests.swift`

**Interfaces:**
- Produces: `protocol DefaultInputDeviceMonitoring`
- Produces: `final class SystemDefaultInputDeviceMonitor`
- Produces: `func currentDeviceID() -> String?`, `func start(handler:) throws`, and `func stop()`

- [ ] **Step 1: Write a failing monitor composition test**

Use an injected change source and device-ID provider so no hardware mutation is required:

```swift
@testable import MeetingAudioCapture
import XCTest

final class DefaultInputDeviceMonitorTests: XCTestCase {
    func testEmitsResolvedDeviceWhenHardwareSourceChanges() throws {
        let source = TestDefaultInputChangeSource()
        let ids = LockedValues(["built-in", "headset"])
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: { ids.removeFirst() }
        )
        let received = LockedValues<String>([])

        XCTAssertEqual(monitor.currentDeviceID(), "built-in")
        try monitor.start { received.append($0) }
        source.emit()

        XCTAssertEqual(received.values(), ["headset"])
        monitor.stop()
        source.emit()
        XCTAssertEqual(received.values(), ["headset"])
    }
}

private final class TestDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func start(handler: @escaping @Sendable () -> Void) throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock { handler = nil }
    }

    func emit() {
        let callback = lock.withLock { handler }
        callback?()
    }
}

private final class LockedValues<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element]

    init(_ values: [Element]) { storage = values }

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }

    func removeFirst() -> Element? {
        lock.withLock { storage.isEmpty ? nil : storage.removeFirst() }
    }

    func values() -> [Element] {
        lock.withLock { storage }
    }
}
```

The test helper implements the internal `DefaultInputChangeSource` protocol and stores the registered callback under a lock.

- [ ] **Step 2: Run the focused test and verify RED**

Run `swift test --filter DefaultInputDeviceMonitorTests`.

Expected: compilation fails because the monitor protocols and implementation do not exist.

- [ ] **Step 3: Implement the monitor and CoreAudio source**

Define:

```swift
protocol DefaultInputDeviceMonitoring: Sendable {
    func currentDeviceID() -> String?
    func start(handler: @escaping @Sendable (String) -> Void) throws
    func stop()
}

protocol DefaultInputChangeSource: Sendable {
    func start(handler: @escaping @Sendable () -> Void) throws
    func stop()
}
```

`SystemDefaultInputDeviceMonitor` composes a `CoreAudioDefaultInputChangeSource` with a provider that returns `AVCaptureDevice.default(for: .audio)?.uniqueID`. Protect its callback with `NSLock`; after `stop()`, source emissions must not invoke the old handler.

`CoreAudioDefaultInputChangeSource` registers one `AudioObjectPropertyListenerBlock` on `AudioObjectID(kAudioObjectSystemObject)` with this address:

```swift
AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
```

Treat any non-`noErr` registration status as `CaptureFailure.setupFailed`, and remove the same listener block in `stop()`.

- [ ] **Step 4: Run monitor and route tests**

Run:

```bash
swift test --filter 'DefaultInputDeviceMonitorTests|MicrophoneRouteControllerTests'
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit the monitor**

```bash
git add Sources/MeetingAudioCapture/Capture/DefaultInputDeviceMonitor.swift Tests/MeetingAudioCaptureTests/DefaultInputDeviceMonitorTests.swift
git commit -m "feat: monitor default input device changes"
```

---

### Task 3: Backend Microphone Reconfiguration

**Files:**
- Modify: `Sources/MeetingAudioCapture/Capture/LegacyMicrophoneCapture.swift`
- Modify: `Sources/MeetingAudioCapture/Capture/ScreenCaptureClient.swift`
- Modify: `Tests/MeetingAudioCaptureTests/LegacyMicrophoneCaptureTests.swift`
- Modify: `Tests/MeetingAudioCaptureTests/CaptureClientTests.swift`

**Interfaces:**
- Consumes: `MicrophoneRouteController`
- Consumes: `DefaultInputDeviceMonitoring`
- Produces: `LegacyMicrophoneCapture.switchDevice(to:) async throws`
- Produces: `ScreenCaptureClient.makeConfiguration(strategy:microphoneDeviceID:)`

- [ ] **Step 1: Write failing configuration and device-resolution tests**

Add tests proving that System Default resolves to the current concrete ID and that macOS 15 configuration captures that ID:

```swift
func testSystemDefaultUsesCurrentDeviceID() {
    XCTAssertEqual(
        ScreenCaptureClient.effectiveMicrophoneID(
            requestedDeviceID: nil,
            currentDefaultDeviceID: "headset"
        ),
        "headset"
    )
}

@available(macOS 15.0, *)
func testMacOS15ConfigurationUsesResolvedMicrophone() {
    let configuration = ScreenCaptureClient.makeConfiguration(
        strategy: .screenCaptureKit,
        microphoneDeviceID: "headset"
    )
    XCTAssertTrue(configuration.captureMicrophone)
    XCTAssertEqual(configuration.microphoneCaptureDeviceID, "headset")
}
```

Extend `LegacyMicrophoneCaptureTests` to prove `resolveDeviceID` selects the new requested ID from an updated device list.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter 'CaptureClientTests|LegacyMicrophoneCaptureTests'
```

Expected: compilation fails because the configuration helpers do not exist.

- [ ] **Step 3: Refactor LegacyMicrophoneCapture for replacement**

Extract the existing queue-confined session construction into `makeSession(deviceID:) throws -> AVCaptureSession`. Implement:

```swift
func switchDevice(to deviceID: String) async throws {
    try await withCheckedThrowingContinuation { continuation in
        queue.async {
            do {
                let replacement = try self.makeSession(deviceID: deviceID)
                self.session?.stopRunning()
                replacement.startRunning()
                self.session = replacement
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

Build the replacement before stopping the existing session so a setup failure leaves the prior device active when possible.

- [ ] **Step 4: Integrate routing into ScreenCaptureClient**

Inject `defaultInputMonitor: any DefaultInputDeviceMonitoring` with `SystemDefaultInputDeviceMonitor()` as the default. During `start`:

1. Resolve `effectiveMicrophoneID` from the requested ID or monitor's current ID.
2. Build the initial stream configuration with that concrete ID.
3. Create `MicrophoneRouteController` whose apply closure calls a private `switchMicrophone(to:strategy:)` method.
4. Start monitoring only when `microphoneDeviceID == nil`; monitoring registration failure leaves recording active.

For `.screenCaptureKit`, create a complete fresh configuration and call:

```swift
try await stream.updateConfiguration(configuration)
```

For `.avCaptureSession`, call:

```swift
try await legacyMicrophone.switchDevice(to: deviceID)
```

In `stop()` and failed startup paths, stop the monitor before stopping capture resources and call `await routeController.stop()`.

- [ ] **Step 5: Run backend-focused tests and verify GREEN**

Run:

```bash
swift test --filter 'CaptureClientTests|LegacyMicrophoneCaptureTests|DefaultInputDeviceMonitorTests|MicrophoneRouteControllerTests'
```

Expected: all focused tests pass with 0 failures.

- [ ] **Step 6: Commit backend integration**

```bash
git add Sources/MeetingAudioCapture/Capture/LegacyMicrophoneCapture.swift Sources/MeetingAudioCapture/Capture/ScreenCaptureClient.swift Tests/MeetingAudioCaptureTests/LegacyMicrophoneCaptureTests.swift Tests/MeetingAudioCaptureTests/CaptureClientTests.swift
git commit -m "fix: follow default microphone while recording"
```

---

### Task 4: Regression, Build, Deployment, And Hardware Verification

**Files:**
- Modify only files required by failures directly caused by Tasks 1-3.

**Interfaces:**
- Consumes the complete capture implementation.
- Produces a verified local app bundle at `.build/MeetingAudioCapture.app`.

- [ ] **Step 1: Run the complete test suite from a fresh scratch path**

Run:

```bash
swift test --scratch-path /private/tmp/meeting-audio-capture-device-switch-tests
```

Expected: all tests pass with 0 failures, including credential and removed post-recording-transcription checks.

- [ ] **Step 2: Build and verify the app**

Run:

```bash
make app
codesign --verify --deep --strict --verbose=2 .build/MeetingAudioCapture.app
```

Expected: release build succeeds and codesign reports the app as valid on disk.

- [ ] **Step 3: Replace the installed app**

Stop the running app, replace `/Applications/MeetingAudioCapture.app` with the verified bundle using `ditto`, relaunch it, and verify the installed executable hash matches `.build/MeetingAudioCapture.app`.

- [ ] **Step 4: Perform the real device-switch test**

1. Select System Default.
2. Start a recording and speak through the built-in microphone for at least 10 seconds.
3. Connect the Bluetooth headset and wait until macOS makes it the default input.
4. Speak through the headset for at least 10 seconds.
5. Disconnect the headset and speak through the built-in microphone again.
6. Stop and save.
7. Inspect the diagnostic microphone CAF and exported right channel; confirm non-silent audio exists in all three sections and only short transition gaps are silent.
8. Confirm system audio remains continuous and transcript entries resume after each switch.

- [ ] **Step 5: Review repository state and commit any verification-only corrections**

Run `git status --short`, `git diff --check`, and the complete test suite again after any correction. Do not include unrelated changes from the original repository worktree.
