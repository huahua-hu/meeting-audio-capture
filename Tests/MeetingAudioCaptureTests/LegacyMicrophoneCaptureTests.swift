@testable import MeetingAudioCapture
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
}
