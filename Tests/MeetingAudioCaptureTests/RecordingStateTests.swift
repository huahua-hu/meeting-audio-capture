@testable import MeetingAudioCapture
import XCTest

final class RecordingStateTests: XCTestCase {
    func testLegalLifecycle() throws {
        var machine = RecordingStateMachine()
        try machine.transition(to: .preparing)
        try machine.transition(to: .recording)
        try machine.transition(to: .paused)
        try machine.transition(to: .recording)
        try machine.transition(to: .stopping)
        try machine.transition(to: .completed)

        XCTAssertEqual(machine.state, .completed)
    }

    func testIdleCannotPause() {
        var machine = RecordingStateMachine()

        XCTAssertThrowsError(try machine.transition(to: .paused)) { error in
            XCTAssertEqual(
                error as? InvalidStateTransition,
                InvalidStateTransition(from: .idle, to: .paused)
            )
        }
    }

    func testFailedAndCompletedSessionsCanReset() throws {
        var completed = RecordingStateMachine()
        try completed.transition(to: .preparing)
        try completed.transition(to: .recording)
        try completed.transition(to: .stopping)
        try completed.transition(to: .completed)
        try completed.transition(to: .idle)

        var failed = RecordingStateMachine()
        try failed.transition(to: .failed(.init(message: "capture stopped")))
        try failed.transition(to: .idle)

        XCTAssertEqual(completed.state, .idle)
        XCTAssertEqual(failed.state, .idle)
    }
}
