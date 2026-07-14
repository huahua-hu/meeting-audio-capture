import Foundation

protocol XFYunWebSocketClient: Sendable {
    func resume() async
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel() async
}

private struct URLSessionXFYunWebSocketClient: XFYunWebSocketClient {
    let task: URLSessionWebSocketTask

    func resume() async {
        task.resume()
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await task.receive()
    }

    func cancel() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

struct XFYunStreamClock: Sendable {
    private static let bytesPerSecond = 16_000 * MemoryLayout<Int16>.size
    private var sentByteCount = 0

    var nextConnectionOffset: TimeInterval {
        TimeInterval(sentByteCount) / TimeInterval(Self.bytesPerSecond)
    }

    mutating func recordSentByteCount(_ count: Int) {
        sentByteCount += count
    }
}

enum XFYunTrackWorker {
    typealias SocketFactory = @Sendable (URL) async throws -> any XFYunWebSocketClient
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private enum WorkerError: Error {
        case server(Int, String)
        case unexpectedInitialEvent
    }

    static func run(
        credentials: XFYunCredentials,
        speaker: TranscriptSpeaker,
        sessionStartedAt: Date,
        stream: AsyncStream<Data>,
        journal: TranscriptJournal,
        socketFactory: @escaping SocketFactory,
        sleep: @escaping Sleeper
    ) async {
        var iterator = stream.makeAsyncIterator()
        var pendingData = await iterator.next()
        var reconnectPolicy = XFYunReconnectPolicy()
        var clock = XFYunStreamClock()

        while !Task.isCancelled, pendingData != nil {
            var socket: (any XFYunWebSocketClient)?
            var receiver: Task<Void, Never>?
            do {
                let url = try XFYunAuthSigner().signedURL(
                    credentials: credentials,
                    timestamp: Int64(Date().timeIntervalSince1970)
                )
                let connection = try await socketFactory(url)
                socket = connection
                await connection.resume()

                let initialEvent = try await receiveEvent(from: connection)
                switch initialEvent {
                case .started:
                    reconnectPolicy.registerStarted()
                case let .failed(code, message):
                    throw WorkerError.server(code, message)
                default:
                    throw WorkerError.unexpectedInitialEvent
                }

                let connectionOffset = clock.nextConnectionOffset
                receiver = receiveResults(
                    from: connection,
                    speaker: speaker,
                    sessionStartedAt: sessionStartedAt,
                    connectionOffset: connectionOffset,
                    journal: journal
                )

                while let data = pendingData, !Task.isCancelled {
                    try await connection.send(.data(data))
                    clock.recordSentByteCount(data.count)
                    pendingData = await iterator.next()
                }

                guard !Task.isCancelled else {
                    receiver?.cancel()
                    await connection.cancel()
                    return
                }
                try await connection.send(.string(#"{"end":true}"#))
                try? await sleep(.seconds(1))
                receiver?.cancel()
                if let receiver { _ = await receiver.result }
                await connection.cancel()
                return
            } catch {
                receiver?.cancel()
                if let receiver { _ = await receiver.result }
                if let socket { await socket.cancel() }
                guard !Task.isCancelled else { return }

                switch reconnectPolicy.registerFailure() {
                case let .retry(delay):
                    do {
                        try await sleep(delay)
                    } catch {
                        return
                    }
                case .giveUp:
                    return
                }
            }
        }
    }

    private static func receiveResults(
        from socket: any XFYunWebSocketClient,
        speaker: TranscriptSpeaker,
        sessionStartedAt: Date,
        connectionOffset: TimeInterval,
        journal: TranscriptJournal
    ) -> Task<Void, Never> {
        Task {
            do {
                while !Task.isCancelled {
                    let event = try await receiveEvent(from: socket)
                    switch event {
                    case let .final(start, end, value) where !value.isEmpty:
                        try await journal.append(.init(
                            speaker: speaker,
                            sessionStartedAt: sessionStartedAt,
                            startTime: connectionOffset + start,
                            endTime: connectionOffset + end,
                            text: value
                        ))
                    case .failed:
                        await socket.cancel()
                        return
                    default:
                        continue
                    }
                }
            } catch {
                await socket.cancel()
            }
        }
    }

    private static func receiveEvent(
        from socket: any XFYunWebSocketClient
    ) async throws -> XFYunServerEvent {
        let message = try await socket.receive()
        let text: String
        switch message {
        case let .string(value): text = value
        case let .data(data): text = String(decoding: data, as: UTF8.self)
        @unknown default: throw WorkerError.unexpectedInitialEvent
        }
        return try XFYunProtocolParser.parse(text)
    }
}

final class XFYunRealtimeTranscriber: @unchecked Sendable {
    private let systemContinuation: AsyncStream<Data>.Continuation
    private let microphoneContinuation: AsyncStream<Data>.Continuation
    private let tasks: [Task<Void, Never>]

    init(credentials: XFYunCredentials, journalURL: URL) {
        let sessionStartedAt = Date()
        let systemPair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(2_048))
        let microphonePair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(2_048))
        systemContinuation = systemPair.continuation
        microphoneContinuation = microphonePair.continuation
        let journal = TranscriptJournal(url: journalURL)
        let socketFactory: XFYunTrackWorker.SocketFactory = { url in
            URLSessionXFYunWebSocketClient(task: URLSession.shared.webSocketTask(with: url))
        }
        let sleeper: XFYunTrackWorker.Sleeper = { duration in
            try await Task.sleep(for: duration)
        }
        tasks = [
            Task.detached {
                await XFYunTrackWorker.run(
                    credentials: credentials,
                    speaker: .other,
                    sessionStartedAt: sessionStartedAt,
                    stream: systemPair.stream,
                    journal: journal,
                    socketFactory: socketFactory,
                    sleep: sleeper
                )
            },
            Task.detached {
                await XFYunTrackWorker.run(
                    credentials: credentials,
                    speaker: .me,
                    sessionStartedAt: sessionStartedAt,
                    stream: microphonePair.stream,
                    journal: journal,
                    socketFactory: socketFactory,
                    sleep: sleeper
                )
            },
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
}
