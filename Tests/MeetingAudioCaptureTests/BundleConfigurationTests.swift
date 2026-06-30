import Foundation
import XCTest

final class BundleConfigurationTests: XCTestCase {
    func testInfoPlistDeclaresRequiredPrivacyPurposes() throws {
        let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNotNil(plist["NSMicrophoneUsageDescription"] as? String)
        XCTAssertNotNil(plist["NSAudioCaptureUsageDescription"] as? String)
        XCTAssertNotNil(plist["NSScreenCaptureUsageDescription"] as? String)
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testInfoPlistDeclaresBundledApplicationIcon() throws {
        let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "Config/AppIcon.icns").path
            )
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
