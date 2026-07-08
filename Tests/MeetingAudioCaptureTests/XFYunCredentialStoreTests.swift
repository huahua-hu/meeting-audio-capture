@testable import MeetingAudioCapture
import XCTest

final class XFYunCredentialStoreTests: XCTestCase {
    func testSaveReadReplaceAndDeleteCredentials() throws {
        let service = "org.meetingaudiocapture.tests.\(UUID().uuidString)"
        let store = XFYunCredentialStore(service: service)
        defer { try? store.deleteCredentials() }

        XCTAssertNil(try store.readCredentials())

        try store.saveCredentials(.init(appID: "test-app", appKey: "test-key"))
        XCTAssertEqual(
            try store.readCredentials(),
            XFYunCredentials(appID: "test-app", appKey: "test-key")
        )

        try store.saveCredentials(.init(appID: "replacement", appKey: "replacement-key"))
        XCTAssertEqual(try store.readCredentials()?.appID, "replacement")

        try store.deleteCredentials()
        XCTAssertNil(try store.readCredentials())
    }
}
