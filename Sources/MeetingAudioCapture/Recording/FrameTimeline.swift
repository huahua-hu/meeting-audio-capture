import AVFAudio
import CoreMedia
import Foundation

struct FrameTimeline: Sendable {
    enum PauseError: Error, Equatable {
        case alreadyPaused
        case notPaused
        case endBeforeStart
    }

    let sampleRate: Double
    let origin: CMTime
    private var pauseStartedAt: CMTime?
    private var accumulatedPause = CMTime.zero

    init(sampleRate: Double, origin: CMTime) {
        self.sampleRate = sampleRate
        self.origin = origin
    }

    func frameIndex(for presentationTime: CMTime) -> AVAudioFramePosition {
        var pauseDuration = accumulatedPause
        if let pauseStartedAt, presentationTime > pauseStartedAt {
            pauseDuration = pauseDuration + (presentationTime - pauseStartedAt)
        }
        let adjusted = presentationTime - origin - pauseDuration
        let seconds = CMTimeGetSeconds(adjusted)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return AVAudioFramePosition((seconds * sampleRate).rounded())
    }

    mutating func beginPause(at time: CMTime) throws {
        guard pauseStartedAt == nil else { throw PauseError.alreadyPaused }
        pauseStartedAt = time
    }

    mutating func endPause(at time: CMTime) throws {
        guard let start = pauseStartedAt else { throw PauseError.notPaused }
        guard time >= start else { throw PauseError.endBeforeStart }
        accumulatedPause = accumulatedPause + (time - start)
        pauseStartedAt = nil
    }
}
