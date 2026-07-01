@testable import MeetingAudioCapture
import XCTest

final class CaptureClientTests: XCTestCase {
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
