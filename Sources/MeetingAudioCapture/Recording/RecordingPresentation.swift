import Foundation

struct MenuBarIndicator: Equatable, Sendable {
    enum Badge: Equatable, Sendable {
        case none
        case dot
        case pause
        case warning
    }

    let symbolName: String
    let badge: Badge
}

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

    static func menuBarIndicator(_ state: RecordingState) -> MenuBarIndicator {
        switch state {
        case .idle, .completed:
            MenuBarIndicator(symbolName: "waveform", badge: .none)
        case .preparing, .recording, .stopping:
            MenuBarIndicator(symbolName: "waveform", badge: .dot)
        case .paused:
            MenuBarIndicator(symbolName: "waveform", badge: .pause)
        case .failed:
            MenuBarIndicator(symbolName: "exclamationmark.triangle", badge: .warning)
        }
    }
}
