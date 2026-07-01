@testable import MeetingAudioCapture
import XCTest

final class AudioTrackLevelerTests: XCTestCase {
    func testMeasuresPeakAndGatedRMSWhileIgnoringSilence() throws {
        let measurement = try AudioTrackLeveler.measure(samples: [0.1, -0.1, 0, 0.0001])

        XCTAssertEqual(measurement.peak, 0.1, accuracy: 0.0001)
        XCTAssertEqual(measurement.gatedRMS, 0.1, accuracy: 0.0001)
        XCTAssertEqual(measurement.activeSampleCount, 2)
    }

    func testSilenceUsesUnityGain() throws {
        let measurement = try AudioTrackLeveler.measure(samples: [0, 0.0001, -0.0001])

        XCTAssertEqual(measurement.activeSampleCount, 0)
        XCTAssertEqual(AudioTrackLeveler.gain(for: measurement), 1, accuracy: 0.0001)
    }

    func testLimitsBoostToTwelveDecibels() throws {
        let measurement = try AudioTrackLeveler.measure(samples: [0.004, -0.004])

        XCTAssertEqual(
            AudioTrackLeveler.gain(for: measurement),
            Float(pow(10, 12.0 / 20.0)),
            accuracy: 0.0001
        )
    }

    func testPeakCeilingTakesPriorityOverRMSTarget() throws {
        let measurement = try AudioTrackLeveler.measure(samples: [0.9, 0.01, -0.01])
        let gain = AudioTrackLeveler.gain(for: measurement)

        XCTAssertLessThanOrEqual(
            gain * measurement.peak,
            Float(pow(10, -3.0 / 20.0)) + 0.0001
        )
    }

    func testRejectsNonFiniteSamples() {
        XCTAssertThrowsError(try AudioTrackLeveler.measure(samples: [.nan])) { error in
            XCTAssertEqual(error as? AudioTrackLevelingError, .nonFiniteSample)
        }
    }
}
