@testable import MeetingAudioCapture
import CoreMedia
import Foundation
import XCTest

final class RecordingCoordinatorTests: XCTestCase {
    func testStartCreatesSessionAndForwardsMicrophoneID() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = FakeCaptureClient()
        let coordinator = RecordingCoordinator(capture: capture, availableCapacity: { _ in 1_000_000_000 })

        try await coordinator.start(
            root: root,
            microphoneDeviceID: "mic-123",
            microphoneName: "Test Microphone"
        )

        XCTAssertEqual(capture.startedMicrophoneID, "mic-123")
        let snapshot = await coordinator.currentSnapshot()
        XCTAssertEqual(snapshot.state, .preparing)
        XCTAssertNil(snapshot.outputFile)
    }

    func testStartRejectsDestinationWithLessThan500MB() async throws {
        let root = FileManager.default.temporaryDirectory
        let capture = FakeCaptureClient()
        let coordinator = RecordingCoordinator(capture: capture, availableCapacity: { _ in 499_999_999 })

        do {
            try await coordinator.start(root: root, microphoneDeviceID: nil, microphoneName: "Mic")
            XCTFail("Expected insufficient-space failure")
        } catch let failure as RecordingFailure {
            XCTAssertTrue(failure.message.contains("500 MB"))
        }
        XCTAssertNil(capture.startedMicrophoneID)
    }
}

private final class FakeCaptureClient: CaptureClient, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<CaptureEvent, Error>.Continuation?
    private(set) var startedMicrophoneID: String?

    func events() -> AsyncThrowingStream<CaptureEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func start(microphoneDeviceID: String?) async throws {
        lock.withLock { startedMicrophoneID = microphoneDeviceID }
    }

    func pause() async {}
    func resume() async {}

    func stop() async {
        lock.withLock { continuation?.finish() }
    }
}
