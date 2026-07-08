@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptJournalTests: XCTestCase {
    func testRendersOneParagraphPerSpeaker() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "transcript.jsonl")
        let journal = TranscriptJournal(url: url)
        try await journal.append(.init(speaker: .interviewer, startTime: 1, endTime: 2, text: "你好"))
        try await journal.append(.init(speaker: .me, startTime: 3, endTime: 4, text: "您好"))
        try await journal.append(.init(speaker: .interviewer, startTime: 5, endTime: 6, text: "请介绍自己"))
        try await journal.close()

        let markdown = try TranscriptJournal.renderMarkdown(from: url, sourceName: "meeting.m4a")
        XCTAssertTrue(markdown.contains("## 面试官\n\n你好请介绍自己"))
        XCTAssertTrue(markdown.contains("## 我\n\n您好"))
    }
}
