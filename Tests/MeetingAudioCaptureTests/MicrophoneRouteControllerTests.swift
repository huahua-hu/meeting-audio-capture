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

    func testRapidChangesApplySeriallyAndFinishOnNewestDevice() async {
        let secondApplyStarted = expectation(description: "second apply starts")
        secondApplyStarted.isInverted = true
        let recorder = SuspendedRouteApplyRecorder(
            secondApplyStarted: secondApplyStarted
        )
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: {},
            applyDevice: { try await recorder.apply($0) }
        )

        let firstUpdate = Task {
            await controller.defaultDeviceDidChange(to: "headset")
        }
        await recorder.waitUntilFirstApplyStarts()
        let secondUpdate = Task {
            await controller.defaultDeviceDidChange(to: "usb-mic")
        }

        await fulfillment(of: [secondApplyStarted], timeout: 0.1)
        await recorder.resumeFirstApply()
        await firstUpdate.value
        await secondUpdate.value

        let result = await recorder.result()
        XCTAssertEqual(result.deviceIDs, ["headset", "usb-mic"])
        XCTAssertEqual(result.maximumInFlightCount, 1)
    }

    func testReturningToActiveDefaultCancelsPendingDifferentTarget() async {
        let recorder = RouteApplyRecorder(failuresRemaining: 1)
        let retryDelay = RetryDelayGate()
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: { await retryDelay.wait() },
            applyDevice: { try await recorder.apply($0) }
        )

        let routeUpdate = Task {
            await controller.defaultDeviceDidChange(to: "headset")
        }
        await retryDelay.waitUntilWaiting()

        await controller.defaultDeviceDidChange(to: "built-in")
        await retryDelay.resume()
        await routeUpdate.value

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, ["headset"])
    }

    func testStopCancelsRetryWorkerBeforeDelayReturns() async {
        let recorder = RouteApplyRecorder(failuresRemaining: 1)
        let retryDelay = RetryDelayGate()
        let controller = MicrophoneRouteController(
            requestedDeviceID: nil,
            initialDefaultDeviceID: "built-in",
            retryDelay: { await retryDelay.wait() },
            applyDevice: { try await recorder.apply($0) }
        )
        let workerFinished = expectation(description: "retry worker finishes")
        let routeUpdate = Task {
            await controller.defaultDeviceDidChange(to: "headset")
            workerFinished.fulfill()
        }
        await retryDelay.waitUntilWaiting()

        await controller.stop()

        await fulfillment(of: [workerFinished], timeout: 0.2)
        await retryDelay.resume()
        await routeUpdate.value

        let deviceIDs = await recorder.deviceIDs()
        XCTAssertEqual(deviceIDs, ["headset"])
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

private actor SuspendedRouteApplyRecorder {
    private let secondApplyStarted: XCTestExpectation
    private var applied: [String] = []
    private var inFlightCount = 0
    private var maximumInFlightCount = 0
    private var firstApplyContinuation: CheckedContinuation<Void, Never>?
    private var firstApplyStartedContinuation: CheckedContinuation<Void, Never>?

    init(secondApplyStarted: XCTestExpectation) {
        self.secondApplyStarted = secondApplyStarted
    }

    func apply(_ deviceID: String) async throws {
        applied.append(deviceID)
        inFlightCount += 1
        maximumInFlightCount = max(maximumInFlightCount, inFlightCount)

        if applied.count == 1 {
            firstApplyStartedContinuation?.resume()
            firstApplyStartedContinuation = nil
            await withCheckedContinuation { continuation in
                firstApplyContinuation = continuation
            }
        } else if inFlightCount > 1 {
            secondApplyStarted.fulfill()
        }

        inFlightCount -= 1
    }

    func waitUntilFirstApplyStarts() async {
        if firstApplyContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            firstApplyStartedContinuation = continuation
        }
    }

    func resumeFirstApply() {
        firstApplyContinuation?.resume()
        firstApplyContinuation = nil
    }

    func result() -> (deviceIDs: [String], maximumInFlightCount: Int) {
        (applied, maximumInFlightCount)
    }
}

private actor RetryDelayGate {
    private var retryContinuation: CheckedContinuation<Void, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private var isCancelled = false

    func wait() async {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if isCancelled {
                    continuation.resume()
                    return
                }

                retryContinuation = continuation
                waitingContinuation?.resume()
                waitingContinuation = nil
            }
        }, onCancel: {
            Task {
                await self.cancel()
            }
        })
    }

    func waitUntilWaiting() async {
        if retryContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            waitingContinuation = continuation
        }
    }

    func resume() {
        retryContinuation?.resume()
        retryContinuation = nil
    }

    private func cancel() {
        isCancelled = true
        resume()
    }
}
