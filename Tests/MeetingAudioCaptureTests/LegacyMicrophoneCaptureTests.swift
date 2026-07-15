@testable import MeetingAudioCapture
import AVFoundation
import XCTest

final class LegacyMicrophoneCaptureTests: XCTestCase {
    func testUsesRequestedDeviceWhenAvailable() {
        XCTAssertEqual(
            LegacyMicrophoneCapture.resolveDeviceID(
                requested: "usb-mic",
                availableIDs: ["built-in", "usb-mic"],
                defaultID: "built-in"
            ),
            "usb-mic"
        )
    }

    func testUsesNewRequestedDeviceFromUpdatedDeviceList() {
        XCTAssertEqual(
            LegacyMicrophoneCapture.resolveDeviceID(
                requested: "headset",
                availableIDs: ["built-in", "headset"],
                defaultID: "headset"
            ),
            "headset"
        )
    }

    func testFallsBackToDefaultWhenRequestedDeviceIsMissing() {
        XCTAssertEqual(
            LegacyMicrophoneCapture.resolveDeviceID(
                requested: "missing",
                availableIDs: ["built-in", "usb-mic"],
                defaultID: "built-in"
            ),
            "built-in"
        )
    }

    func testUsesDefaultWhenNoDeviceWasRequested() {
        XCTAssertEqual(
            LegacyMicrophoneCapture.resolveDeviceID(
                requested: nil,
                availableIDs: ["built-in"],
                defaultID: "built-in"
            ),
            "built-in"
        )
    }

    func testReturnsNilWhenNoMicrophoneExists() {
        XCTAssertNil(
            LegacyMicrophoneCapture.resolveDeviceID(
                requested: nil,
                availableIDs: [],
                defaultID: nil
            )
        )
    }

    func testSwitchBuildsReplacementBeforeStoppingCurrentSession() async throws {
        let recorder = LegacySessionRecorder()
        let capture = LegacyMicrophoneCapture(
            sampleHandler: { _ in },
            sessionFactory: { deviceID, _ in try recorder.makeSession(deviceID: deviceID) },
            startSession: { recorder.start($0) },
            stopSession: { recorder.stop($0) }
        )

        try await capture.start(deviceID: "built-in")
        try await capture.switchDevice(to: "headset")

        XCTAssertEqual(
            recorder.events(),
            ["make:built-in", "start:built-in", "make:headset", "stop:built-in", "start:headset"]
        )
        await capture.stop()
    }

    func testFailedReplacementLeavesCurrentSessionRunning() async throws {
        let recorder = LegacySessionRecorder(failingDeviceID: "headset")
        let capture = LegacyMicrophoneCapture(
            sampleHandler: { _ in },
            sessionFactory: { deviceID, _ in try recorder.makeSession(deviceID: deviceID) },
            startSession: { recorder.start($0) },
            stopSession: { recorder.stop($0) }
        )

        try await capture.start(deviceID: "built-in")

        do {
            try await capture.switchDevice(to: "headset")
            XCTFail("Expected replacement setup to fail")
        } catch {
            XCTAssertEqual(error as? LegacySessionTestFailure, .expected)
        }

        XCTAssertEqual(
            recorder.events(),
            ["make:built-in", "start:built-in", "make:headset"]
        )
        await capture.stop()
    }
}

private enum LegacySessionTestFailure: Error, Equatable {
    case expected
}

private final class LegacySessionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let failingDeviceID: String?
    private var deviceIDsBySession: [ObjectIdentifier: String] = [:]
    private var recordedEvents: [String] = []

    init(failingDeviceID: String? = nil) {
        self.failingDeviceID = failingDeviceID
    }

    func makeSession(deviceID: String?) throws -> AVCaptureSession {
        let deviceID = deviceID ?? "nil"
        return try lock.withLock {
            recordedEvents.append("make:\(deviceID)")
            if deviceID == failingDeviceID {
                throw LegacySessionTestFailure.expected
            }

            let session = AVCaptureSession()
            deviceIDsBySession[ObjectIdentifier(session)] = deviceID
            return session
        }
    }

    func start(_ session: AVCaptureSession) {
        record("start", session: session)
    }

    func stop(_ session: AVCaptureSession) {
        record("stop", session: session)
    }

    func events() -> [String] {
        lock.withLock { recordedEvents }
    }

    private func record(_ action: String, session: AVCaptureSession) {
        lock.withLock {
            let deviceID = deviceIDsBySession[ObjectIdentifier(session)] ?? "unknown"
            recordedEvents.append("\(action):\(deviceID)")
        }
    }
}
