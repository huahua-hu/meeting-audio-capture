import Foundation

struct AudioLevel: Equatable, Sendable {
    let rmsDBFS: Float
    let peakDBFS: Float

    static let silence = AudioLevel(rmsDBFS: -.infinity, peakDBFS: -.infinity)
}

enum AudioLevelMeter {
    static func measure(_ samples: UnsafeBufferPointer<Float>) -> AudioLevel {
        guard !samples.isEmpty else { return .silence }

        var sumOfSquares: Float = 0
        var peak: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
            peak = max(peak, abs(sample))
        }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        return AudioLevel(
            rmsDBFS: decibels(amplitude: rms),
            peakDBFS: decibels(amplitude: peak)
        )
    }

    static func decibels(amplitude: Float) -> Float {
        guard amplitude > 0 else { return -.infinity }
        return 20 * log10(amplitude)
    }
}
