import Foundation

enum TranscriptSpeaker: String, Codable, Sendable {
    case interviewer
    case me

    var displayName: String { self == .interviewer ? "面试官" : "我" }
}

struct TranscriptJournalEntry: Codable, Equatable, Sendable {
    let speaker: TranscriptSpeaker
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

    static func renderMarkdown(from journalURL: URL, sourceName: String) throws -> String {
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
            var text: String
        }
        var turns: [Turn] = []
        for entry in ordered where !entry.text.isEmpty {
            if turns.last?.speaker == entry.speaker {
                turns[turns.count - 1].text += entry.text
            } else {
                turns.append(Turn(speaker: entry.speaker, startTime: entry.startTime, text: entry.text))
            }
        }

        var lines = ["# Meeting Transcript", "", "Source: \(sourceName)", ""]
        for turn in turns {
            let seconds = max(0, Int(turn.startTime))
            let timestamp = String(
                format: "%02d:%02d:%02d",
                seconds / 3_600,
                seconds / 60 % 60,
                seconds % 60
            )
            lines += ["[\(timestamp)] \(turn.speaker.displayName)：\(turn.text)", ""]
        }
        return lines.joined(separator: "\n")
    }
}
