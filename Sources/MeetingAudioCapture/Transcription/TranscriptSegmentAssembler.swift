import Foundation

struct TranscriptSegmentAssembler {
    static func assemble(
        _ segments: [TranscriptionSegment],
        language: AppLanguage,
        maxGap: TimeInterval = 2
    ) -> [TranscriptionSegment] {
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        guard var current = sorted.first else { return [] }
        var result: [TranscriptionSegment] = []
        var previousStartTime = current.startTime

        for segment in sorted.dropFirst() {
            let canMerge = segment.speaker == current.speaker
                && segment.startTime - previousStartTime <= maxGap
            if canMerge {
                current = TranscriptionSegment(
                    startTime: current.startTime,
                    speaker: current.speaker,
                    text: joined(current.text, segment.text, language: language)
                )
            } else {
                result.append(current)
                current = segment
            }
            previousStartTime = segment.startTime
        }
        result.append(current)
        return result
    }

    private static func joined(_ left: String, _ right: String, language: AppLanguage) -> String {
        guard language == .english else { return left + right }
        let punctuation = CharacterSet(charactersIn: ".,!?;:)]}")
        if let first = right.unicodeScalars.first, punctuation.contains(first) {
            return left + right
        }
        return left + " " + right
    }
}
