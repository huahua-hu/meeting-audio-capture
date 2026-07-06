import Foundation

enum TranscriptionSpeaker: String, CaseIterable, Sendable {
    case interviewer
    case me
}

struct TranscriptionSegment: Equatable, Sendable {
    let startTime: TimeInterval
    let speaker: TranscriptionSpeaker
    let text: String
}

struct TranscriptionResult: Equatable, Sendable {
    let session: TranscriptionSession
    let segments: [TranscriptionSegment]
    let warnings: [TranscriptionError]
}

enum TranscriptionError: Error, Equatable, LocalizedError, Sendable {
    case missingDiagnostics
    case missingTrack(String)
    case speechNotAuthorized
    case recognizerUnavailable(String)
    case recognitionFailed(TranscriptionSpeaker, String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDiagnostics:
            return "The recording diagnostics folder is missing."
        case let .missingTrack(filename):
            return "The recording diagnostics track is missing: \(filename)."
        case .speechNotAuthorized:
            return "Speech recognition permission is required."
        case let .recognizerUnavailable(locale):
            return "Speech recognition is unavailable for \(locale)."
        case let .recognitionFailed(speaker, details):
            return "Recognition failed for \(speaker.rawValue): \(details)"
        case let .saveFailed(details):
            return "Unable to save transcript: \(details)"
        }
    }
}
