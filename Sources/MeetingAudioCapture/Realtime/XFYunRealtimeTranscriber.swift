import Foundation

final class XFYunRealtimeTranscriber: @unchecked Sendable {
    private let systemContinuation: AsyncStream<Data>.Continuation
    private let microphoneContinuation: AsyncStream<Data>.Continuation
    private let tasks: [Task<Void, Never>]

    init(credentials: XFYunCredentials, journalURL: URL) {
        let sessionStartedAt = Date()
        let systemPair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(512))
        let microphonePair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(512))
        systemContinuation = systemPair.continuation
        microphoneContinuation = microphonePair.continuation
        let journal = TranscriptJournal(url: journalURL)
        tasks = [
            Self.connectionTask(credentials: credentials, speaker: .other, sessionStartedAt: sessionStartedAt, stream: systemPair.stream, journal: journal),
            Self.connectionTask(credentials: credentials, speaker: .me, sessionStartedAt: sessionStartedAt, stream: microphonePair.stream, journal: journal),
        ]
    }

    func send(_ data: Data, track: CaptureTrack) {
        guard !data.isEmpty else { return }
        switch track {
        case .system: systemContinuation.yield(data)
        case .microphone: microphoneContinuation.yield(data)
        }
    }

    func finish() async {
        systemContinuation.finish()
        microphoneContinuation.finish()
        try? await Task.sleep(for: .seconds(2))
        for task in tasks { task.cancel() }
    }

    private static func connectionTask(
        credentials: XFYunCredentials,
        speaker: TranscriptSpeaker,
        sessionStartedAt: Date,
        stream: AsyncStream<Data>,
        journal: TranscriptJournal
    ) -> Task<Void, Never> {
        Task.detached {
            do {
                let url = try XFYunAuthSigner().signedURL(
                    credentials: credentials,
                    timestamp: Int64(Date().timeIntervalSince1970)
                )
                let socket = URLSession.shared.webSocketTask(with: url)
                socket.resume()
                let receiver = Task {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let text: String
                        switch message {
                        case let .string(value): text = value
                        case let .data(data): text = String(decoding: data, as: UTF8.self)
                        @unknown default: continue
                        }
                        let event = try XFYunProtocolParser.parse(text)
                        if case let .final(start, end, value) = event, !value.isEmpty {
                            try await journal.append(.init(
                                speaker: speaker,
                                sessionStartedAt: sessionStartedAt,
                                startTime: start,
                                endTime: end,
                                text: value
                            ))
                        }
                        if case .failed = event { break }
                    }
                }
                for await data in stream { try await socket.send(.data(data)) }
                try await socket.send(.string(#"{"end":true}"#))
                try? await Task.sleep(for: .seconds(1))
                receiver.cancel()
                socket.cancel(with: .normalClosure, reason: nil)
            } catch {
                // Real-time recognition is best effort; recording remains authoritative.
            }
        }
    }
}
