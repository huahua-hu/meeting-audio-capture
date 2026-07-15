@testable import MeetingAudioCapture
import Foundation
import XCTest

final class CaptureClientTests: XCTestCase {
    func testSystemDefaultUsesCurrentDeviceID() {
        XCTAssertEqual(
            ScreenCaptureClient.effectiveMicrophoneID(
                requestedDeviceID: nil,
                currentDefaultDeviceID: "headset"
            ),
            "headset"
        )
    }

    func testExplicitMicrophoneOverridesCurrentDefaultDeviceID() {
        XCTAssertEqual(
            ScreenCaptureClient.effectiveMicrophoneID(
                requestedDeviceID: "usb-mic",
                currentDefaultDeviceID: "headset"
            ),
            "usb-mic"
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
        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
        XCTAssertEqual(configuration.sampleRate, 48_000)
        XCTAssertEqual(configuration.channelCount, 2)
    }

    func testExplicitSelectionDoesNotStartDefaultInputMonitoring() {
        let monitor = CaptureTestDefaultInputMonitor()
        let routeController = CaptureTestRouteController()
        let routing = MicrophoneRoutingSession(
            requestedDeviceID: "usb-mic",
            monitor: monitor,
            routeController: routeController
        )

        routing.start()

        XCTAssertEqual(monitor.startCallCount, 0)
    }

    func testMonitorRegistrationFailureIsContained() {
        let monitor = CaptureTestDefaultInputMonitor(startError: CaptureTestFailure.expected)
        let routing = MicrophoneRoutingSession(
            requestedDeviceID: nil,
            monitor: monitor,
            routeController: CaptureTestRouteController()
        )

        routing.start()

        XCTAssertEqual(monitor.startCallCount, 1)
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    func testMonitoringReconcilesDeviceChangedDuringRegistration() async {
        let monitor = CaptureTestDefaultInputMonitor(currentID: "headset")
        let appliedDevices = CaptureAppliedDevices()
        let routeController = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { deviceID in await appliedDevices.append(deviceID) }
        )
        let routing = MicrophoneRoutingSession(
            requestedDeviceID: nil,
            monitor: monitor,
            routeController: routeController
        )

        routing.start()
        for _ in 0..<20 where await appliedDevices.values().isEmpty {
            await Task.yield()
        }

        let deviceIDs = await appliedDevices.values()
        XCTAssertEqual(deviceIDs, ["headset"])
        await routing.stop()
    }

    func testRoutingStopsMonitorBeforeRouteController() async {
        let events = CaptureLifecycleEvents()
        let monitor = CaptureTestDefaultInputMonitor(events: events)
        let routing = MicrophoneRoutingSession(
            requestedDeviceID: nil,
            monitor: monitor,
            routeController: CaptureTestRouteController(events: events)
        )

        routing.start()
        await routing.stop()

        XCTAssertEqual(events.values(), ["monitor.stop", "route.stop"])
    }

    func testRetainedMonitorCallbackIsIgnoredAfterRoutingStops() async {
        let monitor = CaptureTestDefaultInputMonitor(retainsHandlerAfterStop: true)
        let appliedDevices = CaptureAppliedDevices()
        let routeController = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { deviceID in await appliedDevices.append(deviceID) }
        )
        let routing = MicrophoneRoutingSession(
            requestedDeviceID: nil,
            monitor: monitor,
            routeController: routeController
        )

        routing.start()
        await routing.stop()
        monitor.emit("headset")
        await Task.yield()
        await Task.yield()

        let deviceIDs = await appliedDevices.values()
        XCTAssertEqual(deviceIDs, [])
    }

    func testMonitorHandlerDoesNotRetainRouteController() {
        let monitor = CaptureTestDefaultInputMonitor(retainsHandlerAfterStop: true)
        weak var weakRouteController: CaptureTestRouteController?

        do {
            let routeController = CaptureTestRouteController()
            weakRouteController = routeController
            let routing = MicrophoneRoutingSession(
                requestedDeviceID: nil,
                monitor: monitor,
                routeController: routeController
            )
            routing.start()
        }

        XCTAssertNil(weakRouteController)
        monitor.emit("headset")
    }

    func testPermissionFailureProvidesActionableGuidance() {
        let failure = CaptureFailure.permissionDenied

        XCTAssertTrue(failure.localizedDescription.contains("Privacy & Security"))
        XCTAssertTrue(failure.localizedDescription.contains("Microphone"))
        XCTAssertTrue(failure.localizedDescription.contains("Screen & System Audio Recording"))
    }

    func testCaptureTracksAreDistinct() {
        XCTAssertNotEqual(CaptureTrack.system, CaptureTrack.microphone)
    }

    func testScreenCaptureClientStopsWhenMicrophonePermissionIsDenied() async {
        let client = ScreenCaptureClient(permissionProvider: DeniedMicrophonePermissionProvider())

        do {
            try await client.start(microphoneDeviceID: nil)
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? CaptureFailure, .permissionDenied)
        }
    }
}

private struct DeniedMicrophonePermissionProvider: MicrophonePermissionProviding {
    func requestPermission() async -> Bool { false }
}

private enum CaptureTestFailure: Error {
    case expected
}

private final class CaptureTestDefaultInputMonitor: DefaultInputDeviceMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let currentID: String?
    private let startError: Error?
    private let retainsHandlerAfterStop: Bool
    private let events: CaptureLifecycleEvents?
    private var handler: (@Sendable (String) -> Void)?
    private var starts = 0
    private var stops = 0

    init(
        currentID: String? = "built-in",
        startError: Error? = nil,
        retainsHandlerAfterStop: Bool = false,
        events: CaptureLifecycleEvents? = nil
    ) {
        self.currentID = currentID
        self.startError = startError
        self.retainsHandlerAfterStop = retainsHandlerAfterStop
        self.events = events
    }

    var startCallCount: Int {
        lock.withLock { starts }
    }

    var stopCallCount: Int {
        lock.withLock { stops }
    }

    func currentDeviceID() -> String? {
        currentID
    }

    func start(handler: @escaping @Sendable (String) -> Void) throws {
        try lock.withLock {
            starts += 1
            if let startError {
                throw startError
            }
            self.handler = handler
        }
    }

    func stop() {
        lock.withLock {
            stops += 1
            events?.append("monitor.stop")
            if !retainsHandlerAfterStop {
                handler = nil
            }
        }
    }

    func emit(_ deviceID: String) {
        let callback = lock.withLock { handler }
        callback?(deviceID)
    }
}

private final class CaptureTestRouteController: MicrophoneRouteControlling, @unchecked Sendable {
    private let events: CaptureLifecycleEvents?

    init(events: CaptureLifecycleEvents? = nil) {
        self.events = events
    }

    func defaultDeviceDidChange(to deviceID: String?) async {}

    func stop() async {
        events?.append("route.stop")
    }
}

private final class CaptureLifecycleEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock { events.append(event) }
    }

    func values() -> [String] {
        lock.withLock { events }
    }
}

private actor CaptureAppliedDevices {
    private var deviceIDs: [String] = []

    func append(_ deviceID: String) {
        deviceIDs.append(deviceID)
    }

    func values() -> [String] {
        deviceIDs
    }
}
