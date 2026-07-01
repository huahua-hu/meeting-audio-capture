import Foundation

enum AudioTrackLevelingError: Error, Equatable, Sendable {
    case nonFiniteSample
}

struct AudioTrackMeasurement: Equatable, Sendable {
    let peak: Float
    let gatedRMS: Float
    let activeSampleCount: Int
}

struct AudioTrackMeasurementAccumulator {
    private var peak: Float = 0
    private var squaredSum = 0.0
    private var activeSampleCount = 0

    mutating func add(_ sample: Float) throws {
        guard sample.isFinite else { throw AudioTrackLevelingError.nonFiniteSample }
        let magnitude = abs(sample)
        peak = max(peak, magnitude)
        if magnitude >= AudioTrackLeveler.activityGate {
            squaredSum += Double(sample) * Double(sample)
            activeSampleCount += 1
        }
    }

    var measurement: AudioTrackMeasurement {
        let gatedRMS = activeSampleCount == 0
            ? 0
            : Float(sqrt(squaredSum / Double(activeSampleCount)))
        return AudioTrackMeasurement(
            peak: peak,
            gatedRMS: gatedRMS,
            activeSampleCount: activeSampleCount
        )
    }
}

enum AudioTrackLeveler {
    static let activityGate = Float(pow(10, -50.0 / 20.0))
    static let targetRMS = Float(pow(10, -24.0 / 20.0))
    static let maximumBoost = Float(pow(10, 12.0 / 20.0))
    static let peakCeiling = Float(pow(10, -3.0 / 20.0))

    static func measure<S: Sequence>(samples: S) throws -> AudioTrackMeasurement where S.Element == Float {
        var accumulator = AudioTrackMeasurementAccumulator()
        for sample in samples {
            try accumulator.add(sample)
        }
        return accumulator.measurement
    }

    static func gain(for measurement: AudioTrackMeasurement) -> Float {
        guard measurement.activeSampleCount > 0,
              measurement.gatedRMS > 0,
              measurement.peak > 0 else { return 1 }
        let rmsGain = targetRMS / measurement.gatedRMS
        let peakGain = peakCeiling / measurement.peak
        return min(rmsGain, maximumBoost, peakGain)
    }
}
