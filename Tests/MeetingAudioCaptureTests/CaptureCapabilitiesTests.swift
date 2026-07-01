@testable import MeetingAudioCapture
import XCTest

final class CaptureCapabilitiesTests: XCTestCase {
    func testMacOS13And14UseAVCaptureSessionMicrophone() {
        XCTAssertEqual(
            CaptureCapabilities.microphoneStrategy(
                for: OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)
            ),
            .avCaptureSession
        )
        XCTAssertEqual(
            CaptureCapabilities.microphoneStrategy(
                for: OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0)
            ),
            .avCaptureSession
        )
    }

    func testMacOS15AndLaterUseScreenCaptureKitMicrophone() {
        XCTAssertEqual(
            CaptureCapabilities.microphoneStrategy(
                for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            ),
            .screenCaptureKit
        )
        XCTAssertEqual(
            CaptureCapabilities.microphoneStrategy(
                for: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            ),
            .screenCaptureKit
        )
    }
}
