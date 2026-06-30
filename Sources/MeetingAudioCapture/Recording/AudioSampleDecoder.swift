import AVFAudio
import CoreMedia
import Foundation

enum AudioSampleDecoder {
    enum DecodeError: Error {
        case missingFormat
        case invalidBuffer
        case allocationFailed
        case conversionFailed(String)
    }

    static func decode(
        _ sampleBuffer: CMSampleBuffer,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
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
            return try convert(source, to: targetFormat)
        }
    }

    private static func convert(
        _ source: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity),
              let converter = AVAudioConverter(from: source.format, to: targetFormat) else {
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
}
