@testable import MeetingAudioCapture
import Foundation
import XCTest

final class XFYunAuthSignerTests: XCTestCase {
    func testBuildsExpectedSignedWebSocketURL() throws {
        let signer = XFYunAuthSigner(endpoint: URL(string: "wss://rtasr.xfyun.cn/v1/ws")!)

        let url = try signer.signedURL(
            credentials: .init(appID: "test-app", appKey: "test-key"),
            timestamp: 1_700_000_000
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map {
            ($0.name, $0.value ?? "")
        })

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(query["appid"], "test-app")
        XCTAssertEqual(query["ts"], "1700000000")
        XCTAssertEqual(query["signa"], "2RJndfgpUCMjT0agTHRPj7G6Zu4=")
    }
}
