import Foundation

struct TranscriptFormatter {
    static func timestamp(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let remainingSeconds = wholeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    static func speakerLabel(_ speaker: TranscriptionSpeaker) -> String {
        switch speaker {
        case .interviewer:
            return "Interviewer"
        case .me:
            return "Me"
        }
    }

    static func markdown(for result: TranscriptionResult) -> String {
        let lines = result.segments.map {
            "[\(timestamp($0.startTime))] \(speakerLabel($0.speaker)): \($0.text)"
        }

        return """
        # Meeting Transcript

        Source: \(result.session.outputFile.lastPathComponent)

        \(lines.joined(separator: "\n"))
        """
    }
}
