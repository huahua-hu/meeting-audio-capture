@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptJournalTests: XCTestCase {
    func testSortsBothTracksByStartTimeAndOnlyMergesAdjacentSpeakerTurns() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "transcript.jsonl")
        let journal = TranscriptJournal(url: url)
        let sessionStartedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-08T19:00:00Z")
        )
        try await journal.append(.init(speaker: .other, sessionStartedAt: sessionStartedAt, startTime: 5, endTime: 6, text: "请介绍自己"))
        try await journal.append(.init(speaker: .me, sessionStartedAt: sessionStartedAt, startTime: 3, endTime: 4, text: "您好"))
        try await journal.append(.init(speaker: .other, sessionStartedAt: sessionStartedAt, startTime: 1, endTime: 2, text: "你好"))
        try await journal.append(.init(speaker: .other, sessionStartedAt: sessionStartedAt, startTime: 7, endTime: 8, text: "最近做了什么"))
        try await journal.close()

        let markdown = try TranscriptJournal.renderMarkdown(
            from: url,
            sourceName: "meeting.m4a",
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )
        let firstInterviewer = try XCTUnwrap(markdown.range(of: "[2026-07-08 19:00:01] 对方：你好"))
        let me = try XCTUnwrap(markdown.range(of: "[2026-07-08 19:00:03] 我：您好"))
        let secondInterviewer = try XCTUnwrap(
            markdown.range(of: "[2026-07-08 19:00:05] 对方：请介绍自己最近做了什么")
        )
        XCTAssertLessThan(firstInterviewer.lowerBound, me.lowerBound)
        XCTAssertLessThan(me.lowerBound, secondInterviewer.lowerBound)
    }
}
