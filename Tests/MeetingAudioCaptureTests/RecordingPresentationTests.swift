@testable import MeetingAudioCapture
import XCTest

final class RecordingPresentationTests: XCTestCase {
    func testFormatsElapsedTimeAsHoursMinutesSeconds() {
        XCTAssertEqual(RecordingPresentation.elapsedTime(0), "00:00:00")
        XCTAssertEqual(RecordingPresentation.elapsedTime(3_661.9), "01:01:01")
    }

    func testProvidesDistinctStateLabels() {
        XCTAssertEqual(RecordingPresentation.stateLabel(.idle, language: .english), "Ready")
        XCTAssertEqual(RecordingPresentation.stateLabel(.preparing, language: .english), "Checking audio…")
        XCTAssertEqual(RecordingPresentation.stateLabel(.recording, language: .english), "Recording")
        XCTAssertEqual(RecordingPresentation.stateLabel(.paused, language: .english), "Paused")
        XCTAssertEqual(RecordingPresentation.stateLabel(.completed, language: .english), "Saved")
        XCTAssertEqual(
            RecordingPresentation.stateLabel(.failed(.init(message: "No audio")), language: .english),
            "Failed"
        )
    }

    func testProvidesChineseStateLabels() {
        XCTAssertEqual(RecordingPresentation.stateLabel(.idle, language: .simplifiedChinese), "就绪")
        XCTAssertEqual(RecordingPresentation.stateLabel(.recording, language: .simplifiedChinese), "录音中")
        XCTAssertEqual(RecordingPresentation.stateLabel(.paused, language: .simplifiedChinese), "已暂停")
        XCTAssertEqual(RecordingPresentation.stateLabel(.stopping, language: .simplifiedChinese), "正在保存…")
    }

    func testMapsRecordingStatesToQuietMenuBarIndicators() {
        XCTAssertEqual(
            RecordingPresentation.menuBarIndicator(.idle),
            MenuBarIndicator(symbolName: "waveform", badge: .none)
        )
        for state in [RecordingState.preparing, .recording, .stopping] {
            XCTAssertEqual(
                RecordingPresentation.menuBarIndicator(state),
                MenuBarIndicator(symbolName: "waveform", badge: .dot)
            )
        }
        XCTAssertEqual(
            RecordingPresentation.menuBarIndicator(.paused),
            MenuBarIndicator(symbolName: "waveform", badge: .pause)
        )
        XCTAssertEqual(
            RecordingPresentation.menuBarIndicator(.completed),
            MenuBarIndicator(symbolName: "waveform", badge: .none)
        )
        XCTAssertEqual(
            RecordingPresentation.menuBarIndicator(.failed(.init(message: "No audio"))),
            MenuBarIndicator(symbolName: "exclamationmark.triangle", badge: .warning)
        )
    }
}
