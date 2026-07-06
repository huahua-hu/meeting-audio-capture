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
    private let stereoChunkDuration: TimeInterval

    init(
        recognizer: any SpeechRecognizing = AppleSpeechRecognizer(),
        stereoChunkDuration: TimeInterval = 50
    ) {
        self.recognizer = recognizer
        self.stereoChunkDuration = stereoChunkDuration
    }

    func transcribe(
        session: TranscriptionSession,
        localeIdentifier: String
    ) async throws -> TranscriptionResult {
        let extractedTracks: ExtractedAudioTracks?
        let chunks: [ExtractedAudioChunk]
        switch session.trackSource {
        case .diagnostics:
            extractedTracks = nil
            chunks = [ExtractedAudioChunk(
                startTime: 0,
                systemAudioFile: session.systemAudioFile,
                microphoneAudioFile: session.microphoneAudioFile
            )]
        case let .stereoExport(url):
            let chunkDuration = stereoChunkDuration
            let tracks = try await Task.detached {
                try StereoChannelExtractor().extract(url: url, chunkDuration: chunkDuration)
            }.value
            extractedTracks = tracks
            chunks = tracks.chunks
        }
        defer { extractedTracks?.cleanup() }

        var segments: [TranscriptionSegment] = []
        var warnings: [TranscriptionError] = []
        var didSucceed = false

        for chunk in chunks {
            async let system = recognize(
                url: chunk.systemAudioFile,
                speaker: TranscriptionSpeaker.interviewer,
                localeIdentifier: localeIdentifier,
                timeOffset: chunk.startTime
            )
            async let microphone = recognize(
                url: chunk.microphoneAudioFile,
                speaker: TranscriptionSpeaker.me,
                localeIdentifier: localeIdentifier,
                timeOffset: chunk.startTime
            )

            for trackResult in await [system, microphone] {
                switch trackResult {
                case let .success(trackSegments):
                    didSucceed = true
                    segments.append(contentsOf: trackSegments)
                case let .failure(error):
                    warnings.append(error)
                }
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
        localeIdentifier: String,
        timeOffset: TimeInterval = 0
    ) async -> Result<[TranscriptionSegment], TranscriptionError> {
        do {
            let recognized = try await recognizer.recognize(url: url, localeIdentifier: localeIdentifier)
            return .success(recognized.map {
                TranscriptionSegment(startTime: $0.startTime + timeOffset, speaker: speaker, text: $0.text)
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
