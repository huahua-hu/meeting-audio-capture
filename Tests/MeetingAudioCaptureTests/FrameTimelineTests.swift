@testable import MeetingAudioCapture
import CoreMedia
import XCTest

final class FrameTimelineTests: XCTestCase {
    func testMapsPresentationTimeTo48KFrames() {
        let timeline = FrameTimeline(
            sampleRate: 48_000,
            origin: CMTime(seconds: 10, preferredTimescale: 48_000)
        )

        XCTAssertEqual(
            timeline.frameIndex(for: CMTime(seconds: 11.25, preferredTimescale: 48_000)),
            60_000
        )
    }

    func testClampsTimesBeforeOriginToZero() {
        let timeline = FrameTimeline(
            sampleRate: 48_000,
            origin: CMTime(seconds: 10, preferredTimescale: 48_000)
        )

        XCTAssertEqual(
            timeline.frameIndex(for: CMTime(seconds: 9, preferredTimescale: 48_000)),
            0
        )
    }

    func testPauseIsRemovedFromOutputTimeline() throws {
        var timeline = FrameTimeline(
            sampleRate: 48_000,
            origin: CMTime(seconds: 10, preferredTimescale: 48_000)
        )
        try timeline.beginPause(at: CMTime(seconds: 12, preferredTimescale: 48_000))
        try timeline.endPause(at: CMTime(seconds: 15, preferredTimescale: 48_000))

        XCTAssertEqual(
            timeline.frameIndex(for: CMTime(seconds: 16, preferredTimescale: 48_000)),
            144_000
        )
    }

    func testRejectsUnbalancedPauseCalls() throws {
        var timeline = FrameTimeline(sampleRate: 48_000, origin: .zero)
        try timeline.beginPause(at: CMTime(seconds: 3, preferredTimescale: 48_000))

        XCTAssertThrowsError(
            try timeline.beginPause(at: CMTime(seconds: 4, preferredTimescale: 48_000))
        )
        XCTAssertThrowsError(
            try timeline.endPause(at: CMTime(seconds: 2, preferredTimescale: 48_000))
        )
    }
}
