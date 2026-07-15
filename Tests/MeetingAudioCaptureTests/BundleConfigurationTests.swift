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
        XCTAssertNil(plist["NSSpeechRecognitionUsageDescription"])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testSourceContainsNoPostRecordingTranscriptionFeature() throws {
        let sourceRoot = projectRoot.appending(path: "Sources")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
        let forbidden = [
            "import Speech",
            "TranscriptionWindowController",
            "selectAudioForTranscription",
            "openTranscriptionForLastRecording",
            "selectAudioAndTranscribe",
        ]

        for path in files {
            let contents = try String(contentsOf: sourceRoot.appending(path: path), encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(contents.contains(symbol), "\(path) contains \(symbol)")
            }
        }
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

    func testInfoPlistDeclaresReleaseVersion() throws {
        let data = try Data(contentsOf: projectRoot.appending(path: "Config/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.3.2")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "5")
    }

    func testMakefileBuildsNamedMacOS13Arm64Artifact() throws {
        let makefile = try String(
            contentsOf: projectRoot.appending(path: "Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("dmg-macos13:"))
        XCTAssertTrue(makefile.contains("--triple arm64-apple-macosx13.0"))
        XCTAssertTrue(makefile.contains("MACOS13_APP_DIR := .build/macos13/$(APP_NAME).app"))
        XCTAssertTrue(makefile.contains("MeetingAudioCapture-0.3.2-macos13-arm64.dmg"))
    }

    func testSourceDoesNotEmbedXFYunCredentialDefaults() throws {
        let sourceRoot = projectRoot.appending(path: "Sources")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") || $0.hasSuffix(".plist") }
        let appKeyPattern = try NSRegularExpression(
            pattern: #"XF_APP_KEY[^\n]*[\"'][0-9a-fA-F]{32}[\"']"#
        )

        for path in files {
            let contents = try String(contentsOf: sourceRoot.appending(path: path), encoding: .utf8)
            XCTAssertFalse(contents.contains("os.getenv(\"XF_APPID\""), path)
            XCTAssertFalse(contents.contains("os.getenv(\"XF_APP_KEY\""), path)
            let range = NSRange(contents.startIndex..., in: contents)
            XCTAssertNil(appKeyPattern.firstMatch(in: contents, range: range), path)
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
