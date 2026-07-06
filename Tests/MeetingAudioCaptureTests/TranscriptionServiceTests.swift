@testable import MeetingAudioCapture
import Foundation
import AVFAudio
import XCTest

final class TranscriptionServiceTests: XCTestCase {
    func testStereoExportRecognitionOffsetsLaterChunks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "existing.m4a")
        try writeStereoAudio(to: output, frames: 9_600)
        let session = try TranscriptionSession.resolveSelectedAudio(outputFile: output)
        let service = TranscriptionService(
            recognizer: FilenameSpeechRecognizer(),
            stereoChunkDuration: 0.1
        )

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        for (actual, expected) in zip(result.segments.map(\.startTime), [0.01, 0.02, 0.11, 0.12]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(result.segments.map(\.speaker), [.interviewer, .me, .interviewer, .me])
    }

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

    func testReturnsEmptySegmentsWhenSuccessfulTrackProducesNoSpeech() async throws {
        let session = makeSession()
        let recognizer = FakeSpeechRecognizer(
            results: [
                session.microphoneAudioFile: []
            ],
            failures: [
                session.systemAudioFile: TranscriptionError.recognitionFailed(.interviewer, "system failed")
            ]
        )
        let service = TranscriptionService(recognizer: recognizer)

        let result = try await service.transcribe(session: session, localeIdentifier: "en-US")

        XCTAssertEqual(result.segments, [])
        XCTAssertEqual(result.warnings, [.recognitionFailed(.interviewer, "system failed")])
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

    private func writeStereoAudio(to url: URL, frames: AVAudioFrameCount) throws {
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2
        ])
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
    }
}

private struct FilenameSpeechRecognizer: SpeechRecognizing {
    func recognize(url: URL, localeIdentifier _: String) async throws -> [RecognizedSpeechSegment] {
        let time = url.lastPathComponent.hasPrefix("system") ? 0.01 : 0.02
        return [RecognizedSpeechSegment(startTime: time, text: url.lastPathComponent)]
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
