import AVFAudio
import Foundation

struct ExtractedAudioChunk: Equatable, Sendable {
    let startTime: TimeInterval
    let systemAudioFile: URL
    let microphoneAudioFile: URL
}

struct ExtractedAudioTracks: Sendable {
    let directory: URL
    let chunks: [ExtractedAudioChunk]

    func cleanup(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: directory)
    }
}

struct StereoChannelExtractor: Sendable {
    private let bufferSize: AVAudioFrameCount = 4_096

    func extract(
        url: URL,
        chunkDuration: TimeInterval = 50,
        fileManager: FileManager = .default
    ) throws -> ExtractedAudioTracks {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        guard format.channelCount == 2, chunkDuration > 0 else {
            throw TranscriptionError.unsupportedAudio("The recording must contain two audio channels.")
        }

        let directory = fileManager.temporaryDirectory
            .appending(path: "MeetingAudioCapture-Transcription-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let framesPerChunk = max(1, AVAudioFramePosition(chunkDuration * format.sampleRate))
            var chunks: [ExtractedAudioChunk] = []
            var chunkIndex = 0
            while input.framePosition < input.length {
                let frameCount = min(framesPerChunk, input.length - input.framePosition)
                let systemURL = directory.appending(path: "system-\(chunkIndex).m4a")
                let microphoneURL = directory.appending(path: "microphone-\(chunkIndex).m4a")
                try writeChunk(
                    input: input,
                    frameCount: frameCount,
                    systemURL: systemURL,
                    microphoneURL: microphoneURL
                )
                chunks.append(ExtractedAudioChunk(
                    startTime: Double(chunkIndex) * chunkDuration,
                    systemAudioFile: systemURL,
                    microphoneAudioFile: microphoneURL
                ))
                chunkIndex += 1
            }
            return ExtractedAudioTracks(directory: directory, chunks: chunks)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func writeChunk(
        input: AVAudioFile,
        frameCount: AVAudioFramePosition,
        systemURL: URL,
        microphoneURL: URL
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.processingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let systemFile = try AVAudioFile(forWriting: systemURL, settings: settings)
        let microphoneFile = try AVAudioFile(forWriting: microphoneURL, settings: settings)
        var remaining = frameCount

        while remaining > 0 {
            let requested = AVAudioFrameCount(min(AVAudioFramePosition(bufferSize), remaining))
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: input.processingFormat,
                frameCapacity: requested
            ), let systemBuffer = AVAudioPCMBuffer(
                pcmFormat: systemFile.processingFormat,
                frameCapacity: requested
            ), let microphoneBuffer = AVAudioPCMBuffer(
                pcmFormat: microphoneFile.processingFormat,
                frameCapacity: requested
            ) else {
                throw TranscriptionError.unsupportedAudio("Unable to allocate audio buffers.")
            }

            try input.read(into: inputBuffer, frameCount: requested)
            let actual = inputBuffer.frameLength
            guard actual > 0,
                  let inputChannels = inputBuffer.floatChannelData,
                  let systemChannel = systemBuffer.floatChannelData?[0],
                  let microphoneChannel = microphoneBuffer.floatChannelData?[0] else {
                throw TranscriptionError.unsupportedAudio("Unable to decode stereo audio.")
            }
            systemBuffer.frameLength = actual
            microphoneBuffer.frameLength = actual
            systemChannel.update(from: inputChannels[0], count: Int(actual))
            microphoneChannel.update(from: inputChannels[1], count: Int(actual))
            try systemFile.write(from: systemBuffer)
            try microphoneFile.write(from: microphoneBuffer)
            remaining -= AVAudioFramePosition(actual)
        }
    }
}
