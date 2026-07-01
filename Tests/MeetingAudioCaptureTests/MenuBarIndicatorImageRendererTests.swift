import AppKit
@testable import MeetingAudioCapture
import XCTest

@MainActor
final class MenuBarIndicatorImageRendererTests: XCTestCase {
    func testRendersFixedSizeTemplateImages() {
        let image = MenuBarIndicatorImageRenderer.image(
            for: MenuBarIndicator(symbolName: "waveform", badge: .dot)
        )

        XCTAssertEqual(image.size, NSSize(width: 26, height: 18))
        XCTAssertTrue(image.isTemplate)
    }

    func testIdleRecordingAndPausedImagesHaveDistinctPixels() throws {
        let idle = MenuBarIndicatorImageRenderer.image(
            for: MenuBarIndicator(symbolName: "waveform", badge: .none)
        )
        let recording = MenuBarIndicatorImageRenderer.image(
            for: MenuBarIndicator(symbolName: "waveform", badge: .dot)
        )
        let paused = MenuBarIndicatorImageRenderer.image(
            for: MenuBarIndicator(symbolName: "waveform", badge: .pause)
        )

        let idleData = try XCTUnwrap(idle.tiffRepresentation)
        let recordingData = try XCTUnwrap(recording.tiffRepresentation)
        let pausedData = try XCTUnwrap(paused.tiffRepresentation)

        XCTAssertNotEqual(idleData, recordingData)
        XCTAssertNotEqual(recordingData, pausedData)
        XCTAssertNotEqual(idleData, pausedData)
    }
}
