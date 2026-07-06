@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptionServiceTests: XCTestCase {
    func testTranscribesBothTracksAndMergesByTimestamp() async throws {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(results: [
            session.systemAudioFile: [
                RecognizedSpeechSegment(startTime: 4, text: "Question two"),
                RecognizedSpeechSegment(startTime: 1, text: "Question one")
            ],
            session.microphoneAudioFile: [
                RecognizedSpeechSegment(startTime: 2, text: "Answer one")
            ]
        ])
        let service = TranscriptionService(recognizer: recognizer)

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        XCTAssertEqual(
            result.segments,
            [
                TranscriptionSegment(startTime: 1, speaker: .interviewer, text: "Question one"),
                TranscriptionSegment(startTime: 2, speaker: .me, text: "Answer one"),
                TranscriptionSegment(startTime: 4, speaker: .interviewer, text: "Question two")
            ]
        )
        XCTAssertEqual(result.warnings, [])
    }

    func testReturnsSuccessfulTrackWithWarningWhenOneTrackFails() async throws {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(
            results: [
                session.microphoneAudioFile: [
                    RecognizedSpeechSegment(startTime: 2, text: "Answer one")
                ]
            ],
            failures: [
                session.systemAudioFile: TranscriptionError.recognitionFailed(.interviewer, "network unavailable")
            ]
        )
        let service = TranscriptionService(recognizer: recognizer)

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        XCTAssertEqual(result.segments, [
            TranscriptionSegment(startTime: 2, speaker: .me, text: "Answer one")
        ])
        XCTAssertEqual(result.warnings, [.recognitionFailed(.interviewer, "network unavailable")])
    }

    func testThrowsWhenBothTracksFail() async {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(failures: [
            session.systemAudioFile: TranscriptionError.recognitionFailed(.interviewer, "system failed"),
            session.microphoneAudioFile: TranscriptionError.recognitionFailed(.me, "microphone failed")
        ])
        let service = TranscriptionService(recognizer: recognizer)

        do {
            _ = try await service.transcribe(session: session, localeIdentifier: "en-US")
            XCTFail("Expected transcription to fail")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .recognitionFailed(.interviewer, "system failed"))
        }
    }

    private func makeSession() -> TranscriptionSession {
        let diagnostics = URL(fileURLWithPath: "/tmp/.diagnostics/Meeting-20260706-091500", isDirectory: true)
        return TranscriptionSession(
            outputFile: URL(fileURLWithPath: "/tmp/Meeting-20260706-091500.m4a"),
            recordingName: "Meeting-20260706-091500",
            diagnosticsDirectory: diagnostics,
            systemAudioFile: diagnostics.appending(path: "system.caf"),
            microphoneAudioFile: diagnostics.appending(path: "microphone.caf")
        )
    }
}

private struct FakeSpeechRecognizer: SpeechRecognizing {
    let results: [URL: [RecognizedSpeechSegment]]
    let failures: [URL: Error]

    init(
        results: [URL: [RecognizedSpeechSegment]] = [:],
        failures: [URL: Error] = [:]
    ) {
        self.results = results
        self.failures = failures
    }

    func recognize(url: URL, localeIdentifier _: String) async throws -> [RecognizedSpeechSegment] {
        if let failure = failures[url] {
            throw failure
        }
        return results[url] ?? []
    }
}
