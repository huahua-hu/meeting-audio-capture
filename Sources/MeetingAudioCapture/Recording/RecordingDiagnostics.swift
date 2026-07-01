import AVFAudio
import Foundation

struct TimelineAnomaly: Codable, Equatable, Sendable {
    let presentationTimeSeconds: Double
    let expectedFrame: AVAudioFramePosition
    let insertedSilenceFrames: AVAudioFramePosition
    let discardedOverlapFrames: AVAudioFramePosition
}

struct TrackTimelineDiagnostics: Codable, Equatable, Sendable {
    private(set) var firstPresentationTimeSeconds: Double?
    private(set) var receivedBufferCount = 0
    private(set) var insertedSilenceFrames: AVAudioFramePosition = 0
    private(set) var discardedOverlapFrames: AVAudioFramePosition = 0
    private(set) var maximumAlignmentDeltaFrames: AVAudioFramePosition = 0
    private(set) var anomalies: [TimelineAnomaly] = []

    mutating func record(
        bufferPTSSeconds: Double,
        expectedFrame: AVAudioFramePosition,
        appendResult: TrackAppendResult
    ) {
        firstPresentationTimeSeconds = firstPresentationTimeSeconds ?? bufferPTSSeconds
        receivedBufferCount += 1
        insertedSilenceFrames += appendResult.insertedSilenceFrames
        discardedOverlapFrames += appendResult.discardedOverlapFrames
        maximumAlignmentDeltaFrames = max(
            maximumAlignmentDeltaFrames,
            max(appendResult.insertedSilenceFrames, appendResult.discardedOverlapFrames)
        )
        if appendResult.insertedSilenceFrames > 0 || appendResult.discardedOverlapFrames > 0 {
            anomalies.append(
                TimelineAnomaly(
                    presentationTimeSeconds: bufferPTSSeconds,
                    expectedFrame: expectedFrame,
                    insertedSilenceFrames: appendResult.insertedSilenceFrames,
                    discardedOverlapFrames: appendResult.discardedOverlapFrames
                )
            )
        }
    }
}

struct RecordingTimelineDiagnostics: Codable, Equatable, Sendable {
    var system = TrackTimelineDiagnostics()
    var microphone = TrackTimelineDiagnostics()
}
