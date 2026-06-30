import AVFAudio
import CoreMedia
import Foundation

final class AudioSampleDecoder {
    enum DecodeError: Error {
        case missingFormat
        case invalidBuffer
        case allocationFailed
        case conversionFailed(String)
    }

    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func decode(_ sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw DecodeError.missingFormat
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)

        return try sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let source = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                bufferListNoCopy: audioBufferList.unsafePointer
            ) else {
                throw DecodeError.invalidBuffer
            }
            return try decodePCM(source)
        }
    }

    func decodePCM(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if formatsMatch(source.format, targetFormat) {
            return try copy(source)
        }

        if converter == nil || converterSourceFormat?.isEqual(source.format) != true {
            guard let newConverter = AVAudioConverter(from: source.format, to: targetFormat) else {
                throw DecodeError.allocationFailed
            }
            converter = newConverter
            converterSourceFormat = source.format
        }
        guard let converter else { throw DecodeError.allocationFailed }

        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw DecodeError.allocationFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error else {
            throw DecodeError.conversionFailed(conversionError?.localizedDescription ?? "Unknown conversion error")
        }
        return output
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == .pcmFormatFloat32
            && rhs.commonFormat == .pcmFormatFloat32
            && !lhs.isInterleaved
            && !rhs.isInterleaved
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
    }

    private func copy(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: source.frameLength
        ), let sourceChannels = source.floatChannelData,
           let outputChannels = output.floatChannelData else {
            throw DecodeError.allocationFailed
        }
        output.frameLength = source.frameLength
        for channel in 0..<Int(targetFormat.channelCount) {
            outputChannels[channel].update(
                from: sourceChannels[channel],
                count: Int(source.frameLength)
            )
        }
        return output
    }
}
