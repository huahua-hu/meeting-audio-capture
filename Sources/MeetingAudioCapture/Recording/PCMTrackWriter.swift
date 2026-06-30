import AVFAudio
import Foundation

final class PCMTrackWriter {
    enum WriterError: Error {
        case alreadyFinished
        case incompatibleFormat
        case allocationFailed
    }

    let format: AVAudioFormat
    private var file: AVAudioFile?
    private(set) var writtenFrameCount: AVAudioFramePosition = 0

    init(url: URL, format: AVAudioFormat) throws {
        self.format = format
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    func append(_ buffer: AVAudioPCMBuffer, atFrame targetFrame: AVAudioFramePosition) throws {
        guard let file else { throw WriterError.alreadyFinished }
        guard buffer.format.sampleRate == format.sampleRate,
              buffer.format.channelCount == format.channelCount,
              buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved else {
            throw WriterError.incompatibleFormat
        }

        if targetFrame > writtenFrameCount {
            try writeSilence(frames: targetFrame - writtenFrameCount, to: file)
        }

        let overlap = max(0, writtenFrameCount - targetFrame)
        guard overlap < AVAudioFramePosition(buffer.frameLength) else { return }
        let output: AVAudioPCMBuffer
        if overlap == 0 {
            output = buffer
        } else {
            output = try slice(buffer, dropping: AVAudioFrameCount(overlap))
        }
        try file.write(from: output)
        writtenFrameCount += AVAudioFramePosition(output.frameLength)
    }

    func finish() throws {
        guard file != nil else { throw WriterError.alreadyFinished }
        file = nil
    }

    private func writeSilence(frames: AVAudioFramePosition, to file: AVAudioFile) throws {
        var remaining = frames
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, 48_000))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw WriterError.allocationFailed
            }
            silence.frameLength = count
            try file.write(from: silence)
            writtenFrameCount += AVAudioFramePosition(count)
            remaining -= AVAudioFramePosition(count)
        }
    }

    private func slice(_ source: AVAudioPCMBuffer, dropping prefix: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let remaining = source.frameLength - prefix
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remaining),
              let sourceChannels = source.floatChannelData,
              let destinationChannels = result.floatChannelData else {
            throw WriterError.allocationFailed
        }
        result.frameLength = remaining
        for channel in 0..<Int(format.channelCount) {
            destinationChannels[channel].update(
                from: sourceChannels[channel].advanced(by: Int(prefix)),
                count: Int(remaining)
            )
        }
        return result
    }
}
