@testable import MeetingAudioCapture
import Foundation
import XCTest

final class RecordingDiagnosticsTests: XCTestCase {
    func testAccumulatesAlignmentEventsAndRoundTripsJSON() throws {
        var track = TrackTimelineDiagnostics()

        track.record(
            bufferPTSSeconds: 1.5,
            expectedFrame: 4_800,
            appendResult: TrackAppendResult(insertedSilenceFrames: 240, discardedOverlapFrames: 0)
        )
        track.record(
            bufferPTSSeconds: 2.0,
            expectedFrame: 9_600,
            appendResult: TrackAppendResult(insertedSilenceFrames: 0, discardedOverlapFrames: 120)
        )

        XCTAssertEqual(track.firstPresentationTimeSeconds, 1.5)
        XCTAssertEqual(track.receivedBufferCount, 2)
        XCTAssertEqual(track.insertedSilenceFrames, 240)
        XCTAssertEqual(track.discardedOverlapFrames, 120)
        XCTAssertEqual(track.maximumAlignmentDeltaFrames, 240)
        XCTAssertEqual(track.anomalies.count, 2)

        let report = RecordingTimelineDiagnostics(system: track, microphone: TrackTimelineDiagnostics())
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(RecordingTimelineDiagnostics.self, from: data), report)
    }

    func testDoesNotCreateAnomalyForAlignedBuffer() {
        var track = TrackTimelineDiagnostics()

        track.record(
            bufferPTSSeconds: 0.25,
            expectedFrame: 0,
            appendResult: TrackAppendResult(insertedSilenceFrames: 0, discardedOverlapFrames: 0)
        )

        XCTAssertEqual(track.receivedBufferCount, 1)
        XCTAssertTrue(track.anomalies.isEmpty)
    }
}
