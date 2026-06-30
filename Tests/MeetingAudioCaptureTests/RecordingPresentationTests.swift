@testable import MeetingAudioCapture
import XCTest

final class RecordingPresentationTests: XCTestCase {
    func testFormatsElapsedTimeAsHoursMinutesSeconds() {
        XCTAssertEqual(RecordingPresentation.elapsedTime(0), "00:00:00")
        XCTAssertEqual(RecordingPresentation.elapsedTime(3_661.9), "01:01:01")
    }

    func testProvidesDistinctStateLabels() {
        XCTAssertEqual(RecordingPresentation.stateLabel(.idle), "Ready")
        XCTAssertEqual(RecordingPresentation.stateLabel(.preparing), "Checking audio…")
        XCTAssertEqual(RecordingPresentation.stateLabel(.recording), "Recording")
        XCTAssertEqual(RecordingPresentation.stateLabel(.paused), "Paused")
        XCTAssertEqual(RecordingPresentation.stateLabel(.completed), "Saved")
        XCTAssertEqual(
            RecordingPresentation.stateLabel(.failed(.init(message: "No audio"))),
            "Failed"
        )
    }
}
