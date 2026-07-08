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
        var lines = ["# Meeting Transcript", "", "Source: \(sourceName)", ""]
        for speaker in [TranscriptSpeaker.interviewer, .me] {
            let paragraph = entries.filter { $0.speaker == speaker }.map(\.text).joined()
            guard !paragraph.isEmpty else { continue }
            lines += ["## \(speaker.displayName)", "", paragraph, ""]
        }
        return lines.joined(separator: "\n")
    }
}
