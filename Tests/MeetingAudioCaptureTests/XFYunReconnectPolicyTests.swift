@testable import MeetingAudioCapture
import XCTest

final class XFYunReconnectPolicyTests: XCTestCase {
    func testRetriesNineFailuresThenGivesUpOnTenth() {
        var policy = XFYunReconnectPolicy()

        for _ in 1...9 {
            XCTAssertEqual(policy.registerFailure(), .retry(after: .seconds(1)))
        }
        XCTAssertEqual(policy.registerFailure(), .giveUp)
    }

    func testStartedConnectionResetsConsecutiveFailures() {
        var policy = XFYunReconnectPolicy()

        for _ in 1...9 {
            _ = policy.registerFailure()
        }
        policy.registerStarted()

        XCTAssertEqual(policy.registerFailure(), .retry(after: .seconds(1)))
        XCTAssertEqual(policy.consecutiveFailures, 1)
    }
}
