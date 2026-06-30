import Foundation

enum RecordingPresentation {
    static func elapsedTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    static func stateLabel(_ state: RecordingState) -> String {
        switch state {
        case .idle: "Ready"
        case .preparing: "Checking audio…"
        case .recording: "Recording"
        case .paused: "Paused"
        case .stopping: "Saving…"
        case .completed: "Saved"
        case .failed: "Failed"
        }
    }
}
