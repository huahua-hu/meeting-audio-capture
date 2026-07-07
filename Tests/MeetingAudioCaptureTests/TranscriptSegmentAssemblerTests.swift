@testable import MeetingAudioCapture
import XCTest

final class TranscriptSegmentAssemblerTests: XCTestCase {
    func testJoinsChineseWordsFromSameSpeakerWithoutSpaces() {
        let result = TranscriptSegmentAssembler.assemble([
            segment(0, .me, "然后"), segment(0.4, .me, "我"),
            segment(0.8, .me, "负责"), segment(1.2, .me, "交付")
        ], language: .simplifiedChinese)

        XCTAssertEqual(result, [segment(0, .me, "然后我负责交付")])
    }

    func testJoinsEnglishWordsWithSpaces() {
        let result = TranscriptSegmentAssembler.assemble([
            segment(0, .interviewer, "Tell"), segment(0.4, .interviewer, "me"),
            segment(0.8, .interviewer, "more")
        ], language: .english)

        XCTAssertEqual(result, [segment(0, .interviewer, "Tell me more")])
    }

    func testStartsNewParagraphWhenSpeakerChanges() {
        let result = TranscriptSegmentAssembler.assemble([
            segment(0, .interviewer, "问题"), segment(0.5, .me, "回答")
        ], language: .simplifiedChinese)

        XCTAssertEqual(result.count, 2)
    }

    func testStartsNewParagraphAfterGapOverTwoSeconds() {
        let result = TranscriptSegmentAssembler.assemble([
            segment(0, .me, "第一段"), segment(2.1, .me, "第二段")
        ], language: .simplifiedChinese)

        XCTAssertEqual(result, [segment(0, .me, "第一段"), segment(2.1, .me, "第二段")])
    }

    private func segment(
        _ startTime: TimeInterval,
        _ speaker: TranscriptionSpeaker,
        _ text: String
    ) -> TranscriptionSegment {
        TranscriptionSegment(startTime: startTime, speaker: speaker, text: text)
    }
}
