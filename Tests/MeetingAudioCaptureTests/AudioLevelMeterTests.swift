@testable import MeetingAudioCapture
import XCTest

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceIsNegativeInfinity() {
        let samples = [Float](repeating: 0, count: 64)
        let level = samples.withUnsafeBufferPointer { AudioLevelMeter.measure($0) }

        XCTAssertEqual(level.rmsDBFS, -.infinity)
        XCTAssertEqual(level.peakDBFS, -.infinity)
    }

    func testConstantHalfScaleIsMinusSixDBFS() {
        let samples = [Float](repeating: 0.5, count: 64)
        let level = samples.withUnsafeBufferPointer { AudioLevelMeter.measure($0) }

        XCTAssertEqual(level.rmsDBFS, -6.0206, accuracy: 0.001)
        XCTAssertEqual(level.peakDBFS, -6.0206, accuracy: 0.001)
    }

    func testPeakIsIndependentFromRMS() {
        let samples: [Float] = [1, 0, 0, 0]
        let level = samples.withUnsafeBufferPointer { AudioLevelMeter.measure($0) }

        XCTAssertEqual(level.rmsDBFS, -6.0206, accuracy: 0.001)
        XCTAssertEqual(level.peakDBFS, 0, accuracy: 0.001)
    }
}
