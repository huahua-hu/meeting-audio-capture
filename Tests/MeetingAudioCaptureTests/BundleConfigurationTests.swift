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

    func testInfoPlistSupportsMacOS13() throws {
        let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
    }

    func testMakefileBuildsNamedMacOS13Arm64Artifact() throws {
        let makefile = try String(
            contentsOf: projectRoot.appending(path: "Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("dmg-macos13:"))
        XCTAssertTrue(makefile.contains("--triple arm64-apple-macosx13.0"))
        XCTAssertTrue(makefile.contains("MACOS13_APP_DIR := .build/macos13/$(APP_NAME).app"))
        XCTAssertTrue(makefile.contains("MeetingAudioCapture-0.1.0-macos13-arm64.dmg"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
