import Foundation
import Speech

struct RecognizedSpeechSegment: Equatable, Sendable {
    let startTime: TimeInterval
    let text: String
}

protocol SpeechRecognizing: Sendable {
    func recognize(url: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment]
}

struct TranscriptionService: Sendable {
    private let recognizer: any SpeechRecognizing

    init(recognizer: any SpeechRecognizing = AppleSpeechRecognizer()) {
        self.recognizer = recognizer
    }

    func transcribe(
        session: TranscriptionSession,
        localeIdentifier: String
    ) async throws -> TranscriptionResult {
        async let system = recognize(
            url: session.systemAudioFile,
            speaker: TranscriptionSpeaker.interviewer,
            localeIdentifier: localeIdentifier
        )
        async let microphone = recognize(
            url: session.microphoneAudioFile,
            speaker: TranscriptionSpeaker.me,
            localeIdentifier: localeIdentifier
        )

        let trackResults = await [system, microphone]
        var segments: [TranscriptionSegment] = []
        var warnings: [TranscriptionError] = []
        var didSucceed = false

        for trackResult in trackResults {
            switch trackResult {
            case let .success(trackSegments):
                didSucceed = true
                segments.append(contentsOf: trackSegments)
            case let .failure(error):
                warnings.append(error)
            }
        }

        if !didSucceed, let firstWarning = warnings.first {
            throw firstWarning
        }

        return TranscriptionResult(
            session: session,
            segments: segments.sorted { $0.startTime < $1.startTime },
            warnings: warnings
        )
    }

    private func recognize(
        url: URL,
        speaker: TranscriptionSpeaker,
        localeIdentifier: String
    ) async -> Result<[TranscriptionSegment], TranscriptionError> {
        do {
            let recognized = try await recognizer.recognize(url: url, localeIdentifier: localeIdentifier)
            return .success(recognized.map {
                TranscriptionSegment(startTime: $0.startTime, speaker: speaker, text: $0.text)
            })
        } catch let error as TranscriptionError {
            return .failure(error)
        } catch {
            return .failure(.recognitionFailed(speaker, error.localizedDescription))
        }
    }
}

struct AppleSpeechRecognizer: SpeechRecognizing {
    func recognize(url: URL, localeIdentifier: String) async throws -> [RecognizedSpeechSegment] {
        let status = await requestAuthorization()
        guard status == .authorized else {
            throw TranscriptionError.speechNotAuthorized
        }

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(localeIdentifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map {
                    RecognizedSpeechSegment(startTime: $0.timestamp, text: $0.substring)
                }
                continuation.resume(returning: segments)
            }
        }
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
