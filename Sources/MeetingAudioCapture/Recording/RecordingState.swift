import Foundation

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
    case completed
    case failed(RecordingFailure)
}

struct RecordingFailure: Error, Equatable, Sendable {
    let message: String
}

struct InvalidStateTransition: Error, Equatable, Sendable {
    let from: RecordingState
    let to: RecordingState
}

struct RecordingStateMachine: Sendable {
    private(set) var state: RecordingState = .idle

    mutating func transition(to next: RecordingState) throws {
        let isAllowed: Bool

        switch (state, next) {
        case (.idle, .preparing),
             (.preparing, .recording),
             (.recording, .paused),
             (.recording, .stopping),
             (.paused, .recording),
             (.paused, .stopping),
             (.stopping, .completed),
             (.completed, .idle),
             (.failed, .idle):
            isAllowed = true
        case (_, .failed):
            isAllowed = true
        default:
            isAllowed = false
        }

        guard isAllowed else {
            throw InvalidStateTransition(from: state, to: next)
        }
        state = next
    }
}
