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
