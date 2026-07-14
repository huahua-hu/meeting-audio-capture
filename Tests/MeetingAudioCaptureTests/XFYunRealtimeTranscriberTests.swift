@testable import MeetingAudioCapture
import Foundation
import XCTest

final class XFYunRealtimeTranscriberTests: XCTestCase {
    func testTrackWorkerReconnectsAndSendsPendingChunk() async throws {
        let firstSocket = ScriptedWebSocket(receiveSteps: [.failure])
        let secondSocket = ScriptedWebSocket(receiveSteps: [.started])
        let factory = ScriptedWebSocketFactory(sockets: [firstSocket, secondSocket])
        let input = XFYunTrackInputStream(bufferLimit: 16)
        let chunk = Data([1, 2, 3, 4])
        input.send(chunk)
        input.finish()

        await Self.runWorker(input: input, factory: factory)

        let createdCount = await factory.createdCount
        let sentDataMessages = await secondSocket.sentDataMessages
        XCTAssertEqual(createdCount, 2)
        XCTAssertEqual(sentDataMessages, [chunk])
    }

    func testReceiveFailureAfterStartedReconnectsWithoutWaitingForMoreAudio() async throws {
        let input = XFYunTrackInputStream(bufferLimit: 16)
        let chunk = Data([1, 2, 3, 4])
        let firstSocket = ScriptedWebSocket(
            receiveSteps: [.started],
            disconnectAfterDataSends: 1
        )
        let secondSocket = ScriptedWebSocket(
            receiveSteps: [.started],
            onResume: { input.finish() }
        )
        let factory = ScriptedWebSocketFactory(sockets: [firstSocket, secondSocket])
        input.send(chunk)

        await Self.runWorker(input: input, factory: factory)

        let createdCount = await factory.createdCount
        let firstMessages = await firstSocket.sentDataMessages
        let secondMessages = await secondSocket.sentDataMessages
        XCTAssertEqual(createdCount, 2)
        XCTAssertEqual(firstMessages, [chunk])
        XCTAssertEqual(secondMessages, [chunk])
    }

    func testSendFailureCancelsSocketBeforeAwaitingBlockedReceiver() async throws {
        let input = XFYunTrackInputStream(bufferLimit: 16)
        let firstSocket = ScriptedWebSocket(
            receiveSteps: [.started],
            dataSendFailures: 1
        )
        let secondSocket = ScriptedWebSocket(
            receiveSteps: [.started],
            onResume: { input.finish() }
        )
        let factory = ScriptedWebSocketFactory(sockets: [firstSocket, secondSocket])
        input.send(Data([1, 2, 3, 4]))

        await Self.runWorker(input: input, factory: factory)

        let createdCount = await factory.createdCount
        let firstCancelCount = await firstSocket.cancelCount
        XCTAssertEqual(createdCount, 2)
        XCTAssertGreaterThanOrEqual(firstCancelCount, 1)
    }

    func testTrackWorkerStopsAfterTenConsecutiveConnectionFailures() async throws {
        let sockets = (1...10).map { _ in ScriptedWebSocket(receiveSteps: [.failure]) }
        let factory = ScriptedWebSocketFactory(sockets: sockets)
        let input = XFYunTrackInputStream(bufferLimit: 16)
        input.send(Data([1, 2, 3, 4]))

        await Self.runWorker(input: input, factory: factory)

        let createdCount = await factory.createdCount
        XCTAssertEqual(createdCount, 10)
    }

    func testFinishRequestPreventsAnotherConnectionAttempt() async throws {
        let socket = ScriptedWebSocket(receiveSteps: [.failure])
        let factory = ScriptedWebSocketFactory(sockets: [socket])
        let input = XFYunTrackInputStream(bufferLimit: 16)
        let controller = XFYunConnectionController()
        input.send(Data([1, 2, 3, 4]))

        await Self.runWorker(
            input: input,
            factory: factory,
            controller: controller,
            sleep: { _ in await controller.requestFinish() }
        )

        let createdCount = await factory.createdCount
        XCTAssertEqual(createdCount, 1)
    }

    func testFinishRequestCanCancelAConnectionBlockedBeforeStarted() async throws {
        let socket = ScriptedWebSocket(receiveSteps: [])
        let factory = ScriptedWebSocketFactory(sockets: [socket])
        let input = XFYunTrackInputStream(bufferLimit: 16)
        let controller = XFYunConnectionController()
        input.send(Data([1, 2, 3, 4]))
        let worker = Task { @Sendable in
            await Self.runWorker(input: input, factory: factory, controller: controller)
        }

        while await socket.resumeCount == 0 {
            await Task.yield()
        }
        await controller.requestFinish()
        await controller.cancelCurrent()
        await worker.value

        let cancelCount = await socket.cancelCount
        XCTAssertGreaterThanOrEqual(cancelCount, 1)
    }

    func testBufferedChunkRetainsAbsoluteTimelineAfterEviction() async throws {
        let input = XFYunTrackInputStream(bufferLimit: 1)
        input.send(Data(repeating: 0, count: 32_000))
        input.send(Data([1, 2, 3, 4]))

        guard case let .audio(chunk) = await input.next() else {
            return XCTFail("Expected an audio chunk")
        }

        XCTAssertEqual(chunk.startByteOffset, 32_000)
        XCTAssertEqual(chunk.startTime, 1, accuracy: 0.000_1)
    }

    func testConnectionFailureSignalDoesNotEvictBufferedAudio() async throws {
        let input = XFYunTrackInputStream(bufferLimit: 1)
        let connectionID = UUID()
        let chunk = Data([1, 2, 3, 4])
        input.send(chunk)
        input.signalConnectionFailure(connectionID)

        guard case .connectionFailed(connectionID) = await input.next() else {
            return XCTFail("Expected the connection failure first")
        }
        guard case let .audio(bufferedChunk) = await input.next() else {
            return XCTFail("Expected the buffered audio to remain available")
        }
        XCTAssertEqual(bufferedChunk.data, chunk)
    }

    private static func runWorker(
        input: XFYunTrackInputStream,
        factory: ScriptedWebSocketFactory,
        controller: XFYunConnectionController = XFYunConnectionController(),
        sleep: @escaping XFYunTrackWorker.Sleeper = { _ in }
    ) async {
        let journalURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: journalURL) }

        await XFYunTrackWorker.run(
            credentials: .init(appID: "test-app", appKey: "test-key"),
            speaker: .me,
            sessionStartedAt: .now,
            input: input,
            journal: TranscriptJournal(url: journalURL),
            controller: controller,
            socketFactory: { _ in try await factory.next() },
            sleep: sleep
        )
    }
}

private actor ScriptedWebSocketFactory {
    private var sockets: [ScriptedWebSocket]
    private(set) var createdCount = 0

    init(sockets: [ScriptedWebSocket]) {
        self.sockets = sockets
    }

    func next() throws -> any XFYunWebSocketClient {
        guard !sockets.isEmpty else { throw TestFailure.noSocket }
        createdCount += 1
        return sockets.removeFirst()
    }
}

private actor ScriptedWebSocket: XFYunWebSocketClient {
    enum ReceiveStep {
        case started
        case failure
    }

    private var receiveSteps: [ReceiveStep]
    private var remainingDataSendFailures: Int
    private var remainingDisconnectingDataSends: Int
    private var pendingDisconnect = false
    private var sentMessages: [URLSessionWebSocketTask.Message] = []
    private var blockedReceivers: [CheckedContinuation<URLSessionWebSocketTask.Message, Error>] = []
    private let onResume: (@Sendable () -> Void)?
    private(set) var cancelCount = 0
    private(set) var resumeCount = 0

    init(
        receiveSteps: [ReceiveStep],
        dataSendFailures: Int = 0,
        disconnectAfterDataSends: Int = 0,
        onResume: (@Sendable () -> Void)? = nil
    ) {
        self.receiveSteps = receiveSteps
        remainingDataSendFailures = dataSendFailures
        remainingDisconnectingDataSends = disconnectAfterDataSends
        self.onResume = onResume
    }

    func resume() async {
        resumeCount += 1
        onResume?()
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if case .data = message, remainingDataSendFailures > 0 {
            remainingDataSendFailures -= 1
            throw TestFailure.disconnected
        }
        sentMessages.append(message)
        if case .data = message, remainingDisconnectingDataSends > 0 {
            remainingDisconnectingDataSends -= 1
            pendingDisconnect = true
            disconnectBlockedReceivers()
        }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !receiveSteps.isEmpty {
            switch receiveSteps.removeFirst() {
            case .started:
                return .string(#"{"action":"started","code":"0","data":""}"#)
            case .failure:
                throw TestFailure.disconnected
            }
        }
        if pendingDisconnect {
            pendingDisconnect = false
            throw TestFailure.disconnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            blockedReceivers.append(continuation)
        }
    }

    func cancel() async {
        cancelCount += 1
        disconnectBlockedReceivers()
    }

    private func disconnectBlockedReceivers() {
        let receivers = blockedReceivers
        blockedReceivers.removeAll()
        for receiver in receivers {
            receiver.resume(throwing: TestFailure.disconnected)
        }
    }

    var sentDataMessages: [Data] {
        sentMessages.compactMap {
            guard case let .data(data) = $0 else { return nil }
            return data
        }
    }
}

private enum TestFailure: Error {
    case disconnected
    case noSocket
}
