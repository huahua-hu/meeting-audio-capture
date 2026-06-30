@testable import MeetingAudioCapture
import Foundation
import XCTest

final class AppLanguagePreferenceTests: XCTestCase {
    func testMissingAndInvalidPreferencesUseEnglish() throws {
        let defaults = try makeDefaults()

        XCTAssertEqual(AppLanguagePreference.load(from: defaults), .english)
        defaults.set("unknown", forKey: AppLanguagePreference.key)
        XCTAssertEqual(AppLanguagePreference.load(from: defaults), .english)
    }

    func testChinesePreferenceRoundTrips() throws {
        let defaults = try makeDefaults()

        AppLanguagePreference.save(.simplifiedChinese, to: defaults)

        XCTAssertEqual(defaults.string(forKey: AppLanguagePreference.key), "zh-Hans")
        XCTAssertEqual(AppLanguagePreference.load(from: defaults), .simplifiedChinese)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "AppLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
