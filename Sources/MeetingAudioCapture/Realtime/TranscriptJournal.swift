import Foundation

enum TranscriptSpeaker: String, Codable, Sendable {
    case other
    case me

    var displayName: String { self == .other ? "对方" : "我" }
}

struct TranscriptJournalEntry: Codable, Equatable, Sendable {
    let speaker: TranscriptSpeaker
    let sessionStartedAt: Date
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

actor TranscriptJournal {
    private let url: URL
    private var handle: FileHandle?

    init(url: URL) { self.url = url }

    func append(_ entry: TranscriptJournalEntry) throws {
        if handle == nil {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            try handle?.seekToEnd()
        }
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)
        try handle?.write(contentsOf: data)
        try handle?.synchronize()
    }

    func close() throws {
        try handle?.close()
        handle = nil
    }

    static func renderMarkdown(
        from journalURL: URL,
        sourceName: String,
        timeZone: TimeZone = .current
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return "" }
        let content = try String(contentsOf: journalURL, encoding: .utf8)
        let decoder = JSONDecoder()
        let entries = content.split(separator: "\n").compactMap {
            try? decoder.decode(TranscriptJournalEntry.self, from: Data($0.utf8))
        }
        guard !entries.isEmpty else { return "" }
        let ordered = entries.enumerated().sorted {
            if $0.element.startTime == $1.element.startTime { return $0.offset < $1.offset }
            return $0.element.startTime < $1.element.startTime
        }.map(\.element)

        struct Turn {
            let speaker: TranscriptSpeaker
            let startTime: TimeInterval
            let startedAt: Date
            var text: String
        }
        var turns: [Turn] = []
        for entry in ordered where !entry.text.isEmpty {
            if turns.last?.speaker == entry.speaker {
                turns[turns.count - 1].text += entry.text
            } else {
                turns.append(Turn(
                    speaker: entry.speaker,
                    startTime: entry.startTime,
                    startedAt: entry.sessionStartedAt.addingTimeInterval(entry.startTime),
                    text: entry.text
                ))
            }
        }

        var lines = ["# Meeting Transcript", "", "Source: \(sourceName)", ""]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for turn in turns {
            let timestamp = formatter.string(from: turn.startedAt)
            lines += ["[\(timestamp)] \(turn.speaker.displayName)：\(turn.text)", ""]
        }
        return lines.joined(separator: "\n")
    }
}
