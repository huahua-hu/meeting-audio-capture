import Foundation

enum RecordingPresentation {
    static func elapsedTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    static func stateLabel(_ state: RecordingState, language: AppLanguage) -> String {
        let key: AppTextKey = switch state {
        case .idle: .ready
        case .preparing: .checkingAudio
        case .recording: .recording
        case .paused: .paused
        case .stopping: .saving
        case .completed: .saved
        case .failed: .failed
        }
        return AppLocalizer.text(key, language: language)
    }
}
