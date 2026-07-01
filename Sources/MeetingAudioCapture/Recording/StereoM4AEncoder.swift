import AVFAudio
import Foundation

enum StereoM4AEncoderError: Error, Sendable {
    case invalidSystemFormat
    case invalidMicrophoneFormat
    case unableToAllocateBuffer
}

struct StereoM4AEncoder: Sendable {
    private let sampleRate = 48_000.0
    private let chunkSize: AVAudioFrameCount = 4_096

    func encode(systemCAF: URL, microphoneCAF: URL, destination: URL) throws {
        let systemFile = try AVAudioFile(forReading: systemCAF)
        let microphoneFile = try AVAudioFile(forReading: microphoneCAF)
        guard systemFile.processingFormat.sampleRate == sampleRate,
              systemFile.processingFormat.channelCount == 2 else {
            throw StereoM4AEncoderError.invalidSystemFormat
        }
        guard microphoneFile.processingFormat.sampleRate == sampleRate,
              microphoneFile.processingFormat.channelCount == 1 else {
            throw StereoM4AEncoderError.invalidMicrophoneFormat
        }

        try? FileManager.default.removeItem(at: destination)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        let outputFile = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let totalFrames = max(systemFile.length, microphoneFile.length)
        var written: AVAudioFramePosition = 0
        while written < totalFrames {
            let requested = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), totalFrames - written))
            guard let systemBuffer = AVAudioPCMBuffer(
                pcmFormat: systemFile.processingFormat,
                frameCapacity: requested
            ), let microphoneBuffer = AVAudioPCMBuffer(
                pcmFormat: microphoneFile.processingFormat,
                frameCapacity: requested
            ), let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFile.processingFormat,
                frameCapacity: requested
            ) else {
                throw StereoM4AEncoderError.unableToAllocateBuffer
            }

            if systemFile.framePosition < systemFile.length {
                try systemFile.read(into: systemBuffer, frameCount: requested)
            }
            if microphoneFile.framePosition < microphoneFile.length {
                try microphoneFile.read(into: microphoneBuffer, frameCount: requested)
            }
            outputBuffer.frameLength = requested

            guard let systemChannels = systemBuffer.floatChannelData,
                  let microphoneChannels = microphoneBuffer.floatChannelData,
                  let outputChannels = outputBuffer.floatChannelData else {
                throw StereoM4AEncoderError.unableToAllocateBuffer
            }
            for frame in 0..<Int(requested) {
                let systemSample: Float
                if frame < Int(systemBuffer.frameLength) {
                    systemSample = 0.5 * systemChannels[0][frame] + 0.5 * systemChannels[1][frame]
                } else {
                    systemSample = 0
                }
                let microphoneSample = frame < Int(microphoneBuffer.frameLength)
                    ? microphoneChannels[0][frame]
                    : 0
                outputChannels[0][frame] = min(1, max(-1, systemSample))
                outputChannels[1][frame] = min(1, max(-1, microphoneSample))
            }
            try outputFile.write(from: outputBuffer)
            written += AVAudioFramePosition(requested)
        }
    }
}
