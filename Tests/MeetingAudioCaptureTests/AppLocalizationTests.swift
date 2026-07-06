@testable import MeetingAudioCapture
import XCTest

final class AppLocalizationTests: XCTestCase {
    func testEnglishIsDefaultAndRawValuesAreStable() {
        XCTAssertEqual(AppLanguage.defaultLanguage, .english)
        XCTAssertEqual(AppLanguage(rawValue: "en"), .english)
        XCTAssertEqual(AppLanguage(rawValue: "zh-Hans"), .simplifiedChinese)
    }

    func testRepresentativeEnglishAndChineseTranslations() {
        XCTAssertEqual(AppLocalizer.text(.startRecording, language: .english), "Start Recording")
        XCTAssertEqual(AppLocalizer.text(.startRecording, language: .simplifiedChinese), "开始录音")
        XCTAssertEqual(AppLocalizer.text(.recording, language: .english), "Recording")
        XCTAssertEqual(AppLocalizer.text(.recording, language: .simplifiedChinese), "录音中")
        XCTAssertEqual(AppLocalizer.text(.transcribe, language: .english), "Transcribe")
        XCTAssertEqual(AppLocalizer.text(.transcribe, language: .simplifiedChinese), "转写")
        XCTAssertEqual(AppLocalizer.text(.interviewer, language: .english), "Interviewer")
        XCTAssertEqual(AppLocalizer.text(.interviewer, language: .simplifiedChinese), "面试官")
    }

    func testEveryKeyHasEnglishAndChineseText() {
        for key in AppTextKey.allCases {
            XCTAssertFalse(AppLocalizer.text(key, language: .english).isEmpty, "Missing English: \(key)")
            XCTAssertFalse(AppLocalizer.text(key, language: .simplifiedChinese).isEmpty, "Missing Chinese: \(key)")
        }
    }

    func testFormattedErrorPreservesDynamicDetails() {
        XCTAssertEqual(
            AppLocalizer.format(.genericErrorFormat, language: .english, "Disk full"),
            "Error: Disk full"
        )
        XCTAssertEqual(
            AppLocalizer.format(.genericErrorFormat, language: .simplifiedChinese, "磁盘已满"),
            "错误：磁盘已满"
        )
    }
}
