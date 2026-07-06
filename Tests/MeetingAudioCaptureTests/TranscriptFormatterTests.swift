@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptFormatterTests: XCTestCase {
    func testFormatsChineseSpeakerLabels() {
        let output = URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a")
        let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
        let session = TranscriptionSession(
            outputFile: output,
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
        let result = TranscriptionResult(
            session: session,
            segments: [
                TranscriptionSegment(startTime: 3, speaker: .interviewer, text: "你好"),
                TranscriptionSegment(startTime: 12, speaker: .me, text: "你好")
            ],
            warnings: []
        )

        let markdown = TranscriptFormatter.markdown(for: result, language: .simplifiedChinese)

        XCTAssertTrue(markdown.contains("面试官: 你好"))
        XCTAssertTrue(markdown.contains("我: 你好"))
    }

    func testFormatsTimestamp() {
        XCTAssertEqual(TranscriptFormatter.timestamp(3.2), "00:00:03")
        XCTAssertEqual(TranscriptFormatter.timestamp(62.9), "00:01:02")
        XCTAssertEqual(TranscriptFormatter.timestamp(3_726.1), "01:02:06")
    }

    func testFormatsMarkdownTranscript() {
        let output = URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a")
        let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
        let session = TranscriptionSession(
            outputFile: output,
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
        let result = TranscriptionResult(
            session: session,
            segments: [
                TranscriptionSegment(startTime: 3, speaker: .interviewer, text: "Tell me about yourself."),
                TranscriptionSegment(startTime: 12, speaker: .me, text: "I build macOS tools.")
            ],
            warnings: []
        )

        XCTAssertEqual(
            TranscriptFormatter.markdown(for: result),
            """
            # Meeting Transcript

            Source: Meeting-20260706-091500.m4a

            [00:00:03] Interviewer: Tell me about yourself.
            [00:00:12] Me: I build macOS tools.
            """
        )
    }
}
