@testable import MeetingAudioCapture
import AVFAudio
import XCTest

final class AudioSampleDecoderTests: XCTestCase {
    func testMatchingFormatCopiesSamplesExactly() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)
        )
        let decoder = AudioSampleDecoder(targetFormat: format)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        input.frameLength = 512
        let inputSamples = try XCTUnwrap(input.floatChannelData?[0])
        for frame in 0..<512 { inputSamples[frame] = Float(frame) / 512 }

        let output = try decoder.decodePCM(input)
        let outputSamples = try XCTUnwrap(output.floatChannelData?[0])

        XCTAssertEqual(output.frameLength, input.frameLength)
        for frame in 0..<512 {
            XCTAssertEqual(outputSamples[frame], inputSamples[frame], accuracy: 0.000_001)
        }
    }

    func testSegmentedResamplingDoesNotCreateBoundaryClicks() throws {
        let sourceFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)
        )
        let targetFormat = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)
        )
        let decoder = AudioSampleDecoder(targetFormat: targetFormat)
        var sourceFrame = 0
        var previousLastSample: Float?

        for _ in 0..<40 {
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 441))
            input.frameLength = 441
            let samples = try XCTUnwrap(input.floatChannelData?[0])
            for frame in 0..<441 {
                let phase = 2 * Double.pi * 440 * Double(sourceFrame + frame) / 44_100
                samples[frame] = Float(sin(phase)) * 0.5
            }
            sourceFrame += 441

            let output = try decoder.decodePCM(input)
            guard output.frameLength > 0 else { continue }
            let converted = try XCTUnwrap(output.floatChannelData?[0])
            if let previousLastSample {
                XCTAssertLessThan(
                    abs(converted[0] - previousLastSample),
                    0.12,
                    "Streaming conversion introduced a block-boundary click"
                )
            }
            previousLastSample = converted[Int(output.frameLength) - 1]
        }
    }
}
