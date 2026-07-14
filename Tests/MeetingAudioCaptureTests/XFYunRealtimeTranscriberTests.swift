@testable import MeetingAudioCapture
import Foundation
import XCTest

final class XFYunRealtimeTranscriberTests: XCTestCase {
    func testTrackWorkerReconnectsAndSendsPendingChunk() async throws {
        let firstSocket = ScriptedWebSocket(steps: [.failure])
        let secondSocket = ScriptedWebSocket(steps: [
            .message(.string(#"{"action":"started","code":"0","data":""}"#)),
        ])
        let factory = ScriptedWebSocketFactory(sockets: [firstSocket, secondSocket])
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        let chunk = Data([1, 2, 3, 4])
        pair.continuation.yield(chunk)
        pair.continuation.finish()
        let journalURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: journalURL) }

        await XFYunTrackWorker.run(
            credentials: .init(appID: "test-app", appKey: "test-key"),
            speaker: .me,
            sessionStartedAt: .now,
            stream: pair.stream,
            journal: TranscriptJournal(url: journalURL),
            socketFactory: { _ in try await factory.next() },
            sleep: { _ in }
        )

        let createdCount = await factory.createdCount
        let sentDataMessages = await secondSocket.sentDataMessages
        XCTAssertEqual(createdCount, 2)
        XCTAssertEqual(sentDataMessages, [chunk])
    }

    func testTrackWorkerStopsAfterTenConsecutiveConnectionFailures() async throws {
        let sockets = (1...10).map { _ in ScriptedWebSocket(steps: [.failure]) }
        let factory = ScriptedWebSocketFactory(sockets: sockets)
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        pair.continuation.yield(Data([1, 2, 3, 4]))

        let journalURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("jsonl")
        defer { try? FileManager.default.removeItem(at: journalURL) }

        await XFYunTrackWorker.run(
            credentials: .init(appID: "test-app", appKey: "test-key"),
            speaker: .me,
            sessionStartedAt: .now,
            stream: pair.stream,
            journal: TranscriptJournal(url: journalURL),
            socketFactory: { _ in try await factory.next() },
            sleep: { _ in }
        )

        let createdCount = await factory.createdCount
        XCTAssertEqual(createdCount, 10)
    }

    func testStreamClockKeepsReconnectedResultsOnOriginalTimeline() {
        var clock = XFYunStreamClock()

        clock.recordSentByteCount(32_000)

        XCTAssertEqual(clock.nextConnectionOffset, 1, accuracy: 0.000_1)
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
    enum Step {
        case message(URLSessionWebSocketTask.Message)
        case failure
    }

    private var steps: [Step]
    private var sentMessages: [URLSessionWebSocketTask.Message] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func resume() async {}

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !steps.isEmpty {
            switch steps.removeFirst() {
            case let .message(message): return message
            case .failure: throw TestFailure.disconnected
            }
        }
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }

    func cancel() async {}

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
