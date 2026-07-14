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
    static let bytesPerSecond = 16_000 * MemoryLayout<Int16>.size

    let data: Data
    let startByteOffset: Int

    var endByteOffset: Int { startByteOffset + data.count }
    var startTime: TimeInterval {
        TimeInterval(startByteOffset) / TimeInterval(Self.bytesPerSecond)
    }

    func suffix(after byteOffset: Int) -> XFYunAudioChunk? {
        guard byteOffset < endByteOffset else { return nil }
        guard byteOffset > startByteOffset else { return self }
        let requestedDrop = byteOffset - startByteOffset
        let alignedDrop = min(data.count, (requestedDrop + 1) / 2 * 2)
        guard alignedDrop < data.count else { return nil }
        return .init(
            data: Data(data.dropFirst(alignedDrop)),
            startByteOffset: startByteOffset + alignedDrop
        )
    }
}

struct XFYunReplayWindow: Sendable {
    static let defaultMaximumByteCount = XFYunAudioChunk.bytesPerSecond * 30

    private let maximumByteCount: Int
    private(set) var chunks: [XFYunAudioChunk] = []

    init(maximumByteCount: Int = defaultMaximumByteCount) {
        precondition(maximumByteCount > 0)
        self.maximumByteCount = maximumByteCount
    }

    mutating func append(_ chunk: XFYunAudioChunk) {
        chunks.append(chunk)
        trimToMaximumSize()
    }

    mutating func acknowledge(through byteOffset: Int) {
        chunks = chunks.compactMap { $0.suffix(after: byteOffset) }
    }

    private mutating func trimToMaximumSize() {
        var overflow = chunks.reduce(0) { $0 + $1.data.count } - maximumByteCount
        while overflow > 0, let first = chunks.first {
            if overflow >= first.data.count {
                overflow -= first.data.count
                chunks.removeFirst()
            } else {
                if let suffix = first.suffix(after: first.startByteOffset + overflow) {
                    chunks[0] = suffix
                } else {
                    chunks.removeFirst()
                }
                overflow = 0
            }
        }
    }
}

enum XFYunTrackInput: Sendable {
    case audio(XFYunAudioChunk)
    case connectionFailed(UUID)
    case progress(UUID)
}

final class XFYunTrackInputStream: @unchecked Sendable {
    private enum NextAction {
        case wait
        case returnValue(XFYunTrackInput?)
    }

    private let bufferLimit: Int
    private let lock = NSLock()
    private var audioQueue: [XFYunAudioChunk] = []
    private var controlQueue: [XFYunTrackInput] = []
    private var waiter: CheckedContinuation<XFYunTrackInput?, Never>?
    private var nextByteOffset = 0
    private var isFinished = false

    init(bufferLimit: Int) {
        precondition(bufferLimit > 0)
        self.bufferLimit = bufferLimit
    }

    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        let delivery: (CheckedContinuation<XFYunTrackInput?, Never>, XFYunAudioChunk)? = lock.withLock {
            guard !isFinished else { return nil }
            let chunk = XFYunAudioChunk(data: data, startByteOffset: nextByteOffset)
            nextByteOffset += data.count
            if let waiter {
                self.waiter = nil
                return (waiter, chunk)
            }
            if audioQueue.count == bufferLimit {
                audioQueue.removeFirst()
            }
            audioQueue.append(chunk)
            return nil
        }
        if let (waiting, chunk) = delivery {
            waiting.resume(returning: .audio(chunk))
        }
    }

    func signalConnectionFailure(_ connectionID: UUID) {
        signalControl(.connectionFailed(connectionID))
    }

    func signalProgress(_ connectionID: UUID) {
        signalControl(.progress(connectionID))
    }

    private func signalControl(_ event: XFYunTrackInput) {
        let waiting: CheckedContinuation<XFYunTrackInput?, Never>? = lock.withLock {
            guard !isFinished else { return nil }
            if let waiter {
                self.waiter = nil
                return waiter
            }
            controlQueue.append(event)
            return nil
        }
        waiting?.resume(returning: event)
    }

    func finish() {
        let waiting: CheckedContinuation<XFYunTrackInput?, Never>? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            let waiting = waiter
            waiter = nil
            return waiting
        }
        waiting?.resume(returning: nil)
    }

    func next() async -> XFYunTrackInput? {
        await withCheckedContinuation { continuation in
            let action: NextAction = lock.withLock {
                if !controlQueue.isEmpty {
                    return .returnValue(controlQueue.removeFirst())
                }
                if !audioQueue.isEmpty {
                    return .returnValue(.audio(audioQueue.removeFirst()))
                }
                if isFinished {
                    return .returnValue(nil)
                }
                precondition(waiter == nil)
                waiter = continuation
                return .wait
            }
            if case let .returnValue(value) = action {
                continuation.resume(returning: value)
            }
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
    private struct Segment {
        let localStartByteOffset: Int
        let originalStartByteOffset: Int
        var byteCount: Int
    }

    private var segments: [Segment] = []
    private var sentByteCount = 0
    private var preparedSegment: Segment?
    private var preparationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var acknowledgedByteOffset: Int?

    func prepareToSend(_ chunk: XFYunAudioChunk) {
        precondition(preparedSegment == nil)
        preparedSegment = .init(
            localStartByteOffset: sentByteCount,
            originalStartByteOffset: chunk.startByteOffset,
            byteCount: chunk.data.count
        )
    }

    func commitPreparedSend() {
        guard let preparedSegment else { return }
        if let lastIndex = segments.indices.last,
           segments[lastIndex].localStartByteOffset + segments[lastIndex].byteCount
                == preparedSegment.localStartByteOffset,
           segments[lastIndex].originalStartByteOffset + segments[lastIndex].byteCount
                == preparedSegment.originalStartByteOffset {
            segments[lastIndex].byteCount += preparedSegment.byteCount
        } else {
            segments.append(preparedSegment)
        }
        sentByteCount += preparedSegment.byteCount
        finishPreparation()
    }

    func rollbackPreparedSend() {
        guard preparedSegment != nil else { return }
        finishPreparation()
    }

    func adjusted(start: TimeInterval, end: TimeInterval) async -> (TimeInterval, TimeInterval) {
        await waitForPreparedSend()
        return (map(time: start, isEnd: false), map(time: end, isEnd: true))
    }

    func acknowledge(end: TimeInterval) async {
        await waitForPreparedSend()
        let mapped = mapToByteOffset(time: end, isEnd: true)
        acknowledgedByteOffset = max(acknowledgedByteOffset ?? 0, mapped)
    }

    private func waitForPreparedSend() async {
        guard preparedSegment != nil else { return }
        await withCheckedContinuation { preparationWaiters.append($0) }
    }

    private func finishPreparation() {
        preparedSegment = nil
        let waiters = preparationWaiters
        preparationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func map(time: TimeInterval, isEnd: Bool) -> TimeInterval {
        TimeInterval(mapToByteOffset(time: time, isEnd: isEnd))
            / TimeInterval(XFYunAudioChunk.bytesPerSecond)
    }

    private func mapToByteOffset(time: TimeInterval, isEnd: Bool) -> Int {
        let localOffset = max(0, Int((time * Double(XFYunAudioChunk.bytesPerSecond)).rounded()))
        let segment = isEnd
            ? segments.last(where: { $0.localStartByteOffset < localOffset })
            : segments.last(where: { $0.localStartByteOffset <= localOffset })
        guard let segment else {
            return segments.first?.originalStartByteOffset ?? localOffset
        }
        let delta = min(localOffset - segment.localStartByteOffset, segment.byteCount)
        return segment.originalStartByteOffset + delta
    }
}

enum XFYunTrackWorker {
    typealias SocketFactory = @Sendable (URL) async throws -> any XFYunWebSocketClient
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private enum WorkerError: Error {
        case server(Int, String)
        case unexpectedInitialEvent
        case connectionClosed
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
        var pendingChunk: XFYunAudioChunk?
        var replayBacklog: [XFYunAudioChunk] = []
        var reconnectPolicy = XFYunReconnectPolicy()

        while pendingChunk == nil {
            guard let event = await input.next() else { return }
            switch event {
            case let .audio(chunk): pendingChunk = chunk
            case .connectionFailed, .progress: continue
            }
        }

        while !Task.isCancelled {
            guard await controller.shouldStartConnection else { return }

            let connectionID = UUID()
            var socket: (any XFYunWebSocketClient)?
            var receiver: Task<Void, Never>?
            let timeline = XFYunConnectionTimeline()
            var inFlight = XFYunReplayWindow()

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

                receiver = receiveResults(
                    from: connection,
                    connectionID: connectionID,
                    speaker: speaker,
                    sessionStartedAt: sessionStartedAt,
                    timeline: timeline,
                    input: input,
                    journal: journal
                )
                connectionLoop: while !Task.isCancelled {
                    if pendingChunk == nil {
                        if !replayBacklog.isEmpty {
                            pendingChunk = replayBacklog.removeFirst()
                            continue
                        }
                        guard let event = await input.next() else { break connectionLoop }
                        switch event {
                        case let .audio(chunk):
                            pendingChunk = chunk
                        case let .connectionFailed(failedID):
                            if failedID == connectionID {
                                throw WorkerError.connectionClosed
                            }
                            continue
                        case let .progress(progressID):
                            if progressID == connectionID,
                               let acknowledged = await timeline.acknowledgedByteOffset {
                                inFlight.acknowledge(through: acknowledged)
                            }
                            continue
                        }
                    }

                    guard let chunk = pendingChunk else { break connectionLoop }
                    await timeline.prepareToSend(chunk)
                    do {
                        try await connection.send(.data(chunk.data))
                    } catch {
                        await timeline.rollbackPreparedSend()
                        throw error
                    }
                    await timeline.commitPreparedSend()
                    inFlight.append(chunk)
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

                let acknowledged = await timeline.acknowledgedByteOffset
                if let acknowledged { inFlight.acknowledge(through: acknowledged) }
                var queued = inFlight.chunks
                if let pendingChunk { queued.append(pendingChunk) }
                queued.append(contentsOf: replayBacklog)
                pendingChunk = queued.first
                replayBacklog = Array(queued.dropFirst())

                guard !Task.isCancelled else { return }
                guard !(await controller.finishRequested) else { return }
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
        receiver?.cancel()
        await socket.cancel()
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
                        await timeline.acknowledge(end: end)
                        input.signalProgress(connectionID)
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
