@testable import MeetingAudioCapture
import Foundation
import XCTest

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testStartPublishesCompletedResult() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = makeSession(root: root)
        let service = TranscriptionService(recognizer: ViewModelFakeSpeechRecognizer(results: [
            session.systemAudioFile: [RecognizedSpeechSegment(startTime: 1, text: "Question")],
            session.microphoneAudioFile: [RecognizedSpeechSegment(startTime: 2, text: "Answer")]
        ]))
        let model = TranscriptionViewModel(session: session, language: .english, service: service)

        await model.start()

        XCTAssertEqual(model.state, .completed)
        XCTAssertTrue(model.transcriptText.contains("Interviewer: Question"))
        XCTAssertTrue(model.transcriptText.contains("Me: Answer"))
    }

    func testSaveTranscriptWritesMarkdownNextToRecording() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = makeSession(root: root)
        let service = TranscriptionService(recognizer: ViewModelFakeSpeechRecognizer(results: [
            session.systemAudioFile: [RecognizedSpeechSegment(startTime: 1, text: "Question")]
        ]))
        let model = TranscriptionViewModel(session: session, language: .english, service: service)
        await model.start()

        try model.saveTranscript()

        let output = root.appending(path: "Meeting-20260706-091500-transcript.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).contains("Question"))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSession(root: URL) -> TranscriptionSession {
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        return TranscriptionSession(
            outputFile: root.appending(path: "Meeting-20260706-091500.m4a"),
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
    }
}

private struct ViewModelFakeSpeechRecognizer: SpeechRecognizing {
    let results: [URL: [RecognizedSpeechSegment]]

    func recognize(url: URL, localeIdentifier _: String) async throws -> [RecognizedSpeechSegment] {
        results[url] ?? []
    }
}
