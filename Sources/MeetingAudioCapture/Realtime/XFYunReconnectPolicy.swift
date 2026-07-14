import Foundation

enum XFYunReconnectDecision: Equatable, Sendable {
    case retry(after: Duration)
    case giveUp
}

struct XFYunReconnectPolicy: Sendable {
    private let maximumConsecutiveFailures: Int
    private let retryDelay: Duration
    private(set) var consecutiveFailures = 0

    init(
        maximumConsecutiveFailures: Int = 10,
        retryDelay: Duration = .seconds(1)
    ) {
        self.maximumConsecutiveFailures = maximumConsecutiveFailures
        self.retryDelay = retryDelay
    }

    mutating func registerFailure() -> XFYunReconnectDecision {
        consecutiveFailures += 1
        if consecutiveFailures >= maximumConsecutiveFailures {
            return .giveUp
        }
        return .retry(after: retryDelay)
    }

    mutating func registerStarted() {
        consecutiveFailures = 0
    }
}
