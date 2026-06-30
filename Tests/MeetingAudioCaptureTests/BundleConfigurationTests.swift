import Foundation
import XCTest

final class BundleConfigurationTests: XCTestCase {
    func testInfoPlistDeclaresRequiredPrivacyPurposes() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNotNil(plist["NSMicrophoneUsageDescription"] as? String)
        XCTAssertNotNil(plist["NSAudioCaptureUsageDescription"] as? String)
        XCTAssertNotNil(plist["NSScreenCaptureUsageDescription"] as? String)
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }
}
