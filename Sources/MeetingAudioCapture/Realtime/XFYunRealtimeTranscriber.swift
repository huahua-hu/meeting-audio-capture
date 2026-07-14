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

struct XFYunAudioChunk: Sendable {
    private static let bytesPerSecond = 16_000 * MemoryLayout<Int16>.size

    let data: Data
    let startByteOffset: Int

    var endByteOffset: Int { startByteOffset + data.count }
    var startTime: TimeInterval {
        TimeInterval(startByteOffset) / TimeInterval(Self.bytesPerSecond)
    }
}

enum XFYunTrackInput: Sendable {
    case audio(XFYunAudioChunk)
    case connectionFailed(UUID)
    case finished
}

final class XFYunTrackInputStream: @unchecked Sendable {
    let stream: AsyncStream<XFYunTrackInput>

    private let continuation: AsyncStream<XFYunTrackInput>.Continuation
    private let lock = NSLock()
    private var nextByteOffset = 0
    private var isFinished = false

    init(bufferLimit: Int) {
        let pair = AsyncStream<XFYunTrackInput>.makeStream(
            bufferingPolicy: .bufferingNewest(bufferLimit)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            guard !isFinished else { return }
            let chunk = XFYunAudioChunk(data: data, startByteOffset: nextByteOffset)
            nextByteOffset += data.count
            continuation.yield(.audio(chunk))
        }
    }

    func signalConnectionFailure(_ connectionID: UUID) {
        lock.withLock {
            guard !isFinished else { return }
            continuation.yield(.connectionFailed(connectionID))
        }
    }

    func finish() {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true
            continuation.yield(.finished)
            continuation.finish()
        }
    }
}

actor XFYunConnectionController {
    private var socket: (any XFYunWebSocketClient)?
    private(set) var finishRequested = false

    var shouldStartConnection: Bool { !finishRequested }

    func install(_ newSocket: any XFYunWebSocketClient) async -> Bool {
        guard !finishRequested else {
            await newSocket.cancel()
            return false
        }
        socket = newSocket
        return true
    }

    func clear() {
        socket = nil
    }

    func requestFinish() {
        finishRequested = true
    }

    func cancelCurrent() async {
        await socket?.cancel()
    }
}

private actor XFYunConnectionTimeline {
    private var offset: TimeInterval?

    func beginIfNeeded(at time: TimeInterval) {
        if offset == nil { offset = time }
    }

    func adjusted(start: TimeInterval, end: TimeInterval) -> (TimeInterval, TimeInterval) {
        let offset = offset ?? 0
        return (offset + start, offset + end)
    }
}

enum XFYunTrackWorker {
    typealias SocketFactory = @Sendable (URL) async throws -> any XFYunWebSocketClient
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private enum WorkerError: Error {
        case server(Int, String)
        case unexpectedInitialEvent
        case connectionClosed
        case bufferGap
    }

    static func run(
        credentials: XFYunCredentials,
        speaker: TranscriptSpeaker,
        sessionStartedAt: Date,
        input: XFYunTrackInputStream,
        journal: TranscriptJournal,
        controller: XFYunConnectionController,
        socketFactory: @escaping SocketFactory,
        sleep: @escaping Sleeper
    ) async {
        var iterator = input.stream.makeAsyncIterator()
        var pendingChunk: XFYunAudioChunk?
        var reconnectPolicy = XFYunReconnectPolicy()

        while pendingChunk == nil {
            guard let event = await iterator.next() else { return }
            switch event {
            case let .audio(chunk): pendingChunk = chunk
            case .finished: return
            case .connectionFailed: continue
            }
        }

        while !Task.isCancelled {
            guard await controller.shouldStartConnection else { return }

            let connectionID = UUID()
            var socket: (any XFYunWebSocketClient)?
            var receiver: Task<Void, Never>?
            var shouldRetryWithoutFailure = false

            do {
                let url = try XFYunAuthSigner().signedURL(
                    credentials: credentials,
                    timestamp: Int64(Date().timeIntervalSince1970)
                )
                let connection = try await socketFactory(url)
                socket = connection
                guard await controller.install(connection) else { return }
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

                let timeline = XFYunConnectionTimeline()
                receiver = receiveResults(
                    from: connection,
                    connectionID: connectionID,
                    speaker: speaker,
                    sessionStartedAt: sessionStartedAt,
                    timeline: timeline,
                    input: input,
                    journal: journal
                )
                var expectedByteOffset: Int?

                connectionLoop: while !Task.isCancelled {
                    if pendingChunk == nil {
                        guard let event = await iterator.next() else { break connectionLoop }
                        switch event {
                        case let .audio(chunk):
                            pendingChunk = chunk
                        case let .connectionFailed(failedID):
                            if failedID == connectionID {
                                throw WorkerError.connectionClosed
                            }
                            continue
                        case .finished:
                            break connectionLoop
                        }
                    }

                    guard let chunk = pendingChunk else { break connectionLoop }
                    if let expectedByteOffset, chunk.startByteOffset != expectedByteOffset {
                        shouldRetryWithoutFailure = true
                        throw WorkerError.bufferGap
                    }
                    await timeline.beginIfNeeded(at: chunk.startTime)
                    try await connection.send(.data(chunk.data))
                    expectedByteOffset = chunk.endByteOffset
                    pendingChunk = nil
                }

                guard !Task.isCancelled else {
                    await cleanup(connection, receiver: receiver, controller: controller)
                    return
                }
                try await connection.send(.string(#"{"end":true}"#))
                try? await sleep(.seconds(1))
                await cleanup(connection, receiver: receiver, controller: controller)
                return
            } catch {
                if let socket {
                    await cleanup(socket, receiver: receiver, controller: controller)
                } else {
                    await controller.clear()
                }
                guard !Task.isCancelled else { return }
                guard !(await controller.finishRequested) else { return }

                if shouldRetryWithoutFailure {
                    continue
                }
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

    private static func cleanup(
        _ socket: any XFYunWebSocketClient,
        receiver: Task<Void, Never>?,
        controller: XFYunConnectionController
    ) async {
        await socket.cancel()
        receiver?.cancel()
        if let receiver { _ = await receiver.result }
        await controller.clear()
    }

    private static func receiveResults(
        from socket: any XFYunWebSocketClient,
        connectionID: UUID,
        speaker: TranscriptSpeaker,
        sessionStartedAt: Date,
        timeline: XFYunConnectionTimeline,
        input: XFYunTrackInputStream,
        journal: TranscriptJournal
    ) -> Task<Void, Never> {
        Task {
            do {
                while !Task.isCancelled {
                    let event = try await receiveEvent(from: socket)
                    switch event {
                    case let .final(start, end, value) where !value.isEmpty:
                        let adjusted = await timeline.adjusted(start: start, end: end)
                        try await journal.append(.init(
                            speaker: speaker,
                            sessionStartedAt: sessionStartedAt,
                            startTime: adjusted.0,
                            endTime: adjusted.1,
                            text: value
                        ))
                    case .failed:
                        input.signalConnectionFailure(connectionID)
                        await socket.cancel()
                        return
                    default:
                        continue
                    }
                }
            } catch {
                if !Task.isCancelled {
                    input.signalConnectionFailure(connectionID)
                    await socket.cancel()
                }
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
    private let systemInput: XFYunTrackInputStream
    private let microphoneInput: XFYunTrackInputStream
    private let controllers: [XFYunConnectionController]
    private let tasks: [Task<Void, Never>]
    private let journal: TranscriptJournal

    init(credentials: XFYunCredentials, journalURL: URL) {
        let sessionStartedAt = Date()
        let systemInput = XFYunTrackInputStream(bufferLimit: 2_048)
        let microphoneInput = XFYunTrackInputStream(bufferLimit: 2_048)
        let systemController = XFYunConnectionController()
        let microphoneController = XFYunConnectionController()
        let journal = TranscriptJournal(url: journalURL)
        let socketFactory: XFYunTrackWorker.SocketFactory = { url in
            URLSessionXFYunWebSocketClient(task: URLSession.shared.webSocketTask(with: url))
        }
        let sleeper: XFYunTrackWorker.Sleeper = { duration in
            try await Task.sleep(for: duration)
        }

        self.systemInput = systemInput
        self.microphoneInput = microphoneInput
        controllers = [systemController, microphoneController]
        self.journal = journal
        tasks = [
            Task.detached {
                await XFYunTrackWorker.run(
                    credentials: credentials,
                    speaker: .other,
                    sessionStartedAt: sessionStartedAt,
                    input: systemInput,
                    journal: journal,
                    controller: systemController,
                    socketFactory: socketFactory,
                    sleep: sleeper
                )
            },
            Task.detached {
                await XFYunTrackWorker.run(
                    credentials: credentials,
                    speaker: .me,
                    sessionStartedAt: sessionStartedAt,
                    input: microphoneInput,
                    journal: journal,
                    controller: microphoneController,
                    socketFactory: socketFactory,
                    sleep: sleeper
                )
            },
        ]
    }

    func send(_ data: Data, track: CaptureTrack) {
        switch track {
        case .system: systemInput.send(data)
        case .microphone: microphoneInput.send(data)
        }
    }

    func finish() async {
        systemInput.finish()
        microphoneInput.finish()
        for controller in controllers { await controller.requestFinish() }

        try? await Task.sleep(for: .seconds(2))
        for task in tasks { task.cancel() }
        for controller in controllers { await controller.cancelCurrent() }
        for task in tasks { _ = await task.result }
        try? await journal.close()
    }
}
