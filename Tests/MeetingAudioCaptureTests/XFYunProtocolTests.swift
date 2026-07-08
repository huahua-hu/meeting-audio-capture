@testable import MeetingAudioCapture
import Foundation
import XCTest

final class XFYunProtocolTests: XCTestCase {
    func testParsesStartedEvent() throws {
        let event = try XFYunProtocolParser.parse(#"{"action":"started","code":"0","data":""}"#)
        XCTAssertEqual(event, .started)
    }

    func testParsesFinalResultTextAndTimes() throws {
        let nested = #"{"seg_id":0,"cn":{"st":{"bg":"100","ed":"200","type":"0","rt":[{"ws":[{"cw":[{"w":"你好","wp":"n"}]},{"cw":[{"w":"世界","wp":"n"}]}]}]}}}"#
        let nestedData = try JSONEncoder().encode(nested)
        let escaped = try XCTUnwrap(String(data: nestedData, encoding: .utf8))
        let event = try XFYunProtocolParser.parse(
            #"{"action":"result","code":"0","data":\#(escaped)}"#
        )

        XCTAssertEqual(event, .final(startTime: 0.1, endTime: 0.2, text: "你好世界"))
    }

    func testParsesErrorEvent() throws {
        let event = try XFYunProtocolParser.parse(
            #"{"action":"error","code":"10163","desc":"invalid signature","data":""}"#
        )
        XCTAssertEqual(event, .failed(code: 10_163, message: "invalid signature"))
    }
}
