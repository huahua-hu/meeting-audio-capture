import Foundation
import Speech

private typealias TrackRecognitionResult = Result<[TranscriptionSegment], TranscriptionError>

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
    private let processorCount: Int
    private let retryDelay: Duration

    init(
        recognizer: any SpeechRecognizing = AppleSpeechRecognizer(),
        stereoChunkDuration: TimeInterval = 50,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        retryDelay: Duration = .milliseconds(400)
    ) {
        self.recognizer = recognizer
        self.stereoChunkDuration = stereoChunkDuration
        self.processorCount = processorCount
        self.retryDelay = retryDelay
    }

    static func chunkConcurrency(processorCount: Int) -> Int {
        min(max(2, processorCount / 2), 6)
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

        let trackResults = await recognizeChunks(
            chunks,
            localeIdentifier: localeIdentifier,
            concurrency: Self.chunkConcurrency(processorCount: processorCount)
        )
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

        let language: AppLanguage = localeIdentifier.lowercased().hasPrefix("zh")
            ? .simplifiedChinese
            : .english
        return TranscriptionResult(
            session: session,
            segments: TranscriptSegmentAssembler.assemble(segments, language: language),
            warnings: warnings
        )
    }

    private func recognizeChunks(
        _ chunks: [ExtractedAudioChunk],
        localeIdentifier: String,
        concurrency: Int
    ) async -> [TrackRecognitionResult] {
        await withTaskGroup(of: [TrackRecognitionResult].self) { group in
            let initialCount = min(concurrency, chunks.count)
            var nextIndex = initialCount
            var collected: [TrackRecognitionResult] = []

            for chunk in chunks.prefix(initialCount) {
                group.addTask {
                    await recognizeChunk(chunk, localeIdentifier: localeIdentifier)
                }
            }

            while let chunkResults = await group.next() {
                collected.append(contentsOf: chunkResults)
                if nextIndex < chunks.count {
                    let chunk = chunks[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await recognizeChunk(chunk, localeIdentifier: localeIdentifier)
                    }
                }
            }
            return collected
        }
    }

    private func recognizeChunk(
        _ chunk: ExtractedAudioChunk,
        localeIdentifier: String
    ) async -> [TrackRecognitionResult] {
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
        return await [system, microphone]
    }

    private func recognize(
        url: URL,
        speaker: TranscriptionSpeaker,
        localeIdentifier: String,
        timeOffset: TimeInterval = 0
    ) async -> Result<[TranscriptionSegment], TranscriptionError> {
        for attempt in 0..<3 {
            do {
                let recognized = try await recognizer.recognize(url: url, localeIdentifier: localeIdentifier)
                return .success(recognized.map {
                    TranscriptionSegment(startTime: $0.startTime + timeOffset, speaker: speaker, text: $0.text)
                })
            } catch let error as TranscriptionError {
                return .failure(error)
            } catch {
                let nsError = error as NSError
                if isNoSpeech(error: error, nsError: nsError) {
                    return .success([])
                }
                if attempt < 2, isTransient(error: error, nsError: nsError) {
                    try? await Task.sleep(for: retryDelay)
                    continue
                }
                return .failure(.recognitionFailed(speaker, error.localizedDescription))
            }
        }
        return .failure(.recognitionFailed(speaker, "Recognition retry limit reached."))
    }

    private func isNoSpeech(error: Error, nsError: NSError) -> Bool {
        (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110)
            || error.localizedDescription.localizedCaseInsensitiveContains("no speech detected")
    }

    private func isTransient(error: Error, nsError: NSError) -> Bool {
        if nsError.domain == "kAFAssistantErrorDomain", [1100, 1101, 1107, 203].contains(nsError.code) {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("busy")
            || message.contains("rate limit")
            || message.contains("temporarily unavailable")
            || message.contains("connection interrupted")
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
