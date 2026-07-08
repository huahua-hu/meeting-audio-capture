@testable import MeetingAudioCapture
import AVFAudio
import XCTest

final class RealtimePCMEncoderTests: XCTestCase {
    func testDownmixesStereoAndDownsamples48kTo16k() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 6))
        buffer.frameLength = 6
        for index in 0..<6 {
            buffer.floatChannelData?[0][index] = 0.5
            buffer.floatChannelData?[1][index] = -0.25
        }

        var encoder = RealtimePCMEncoder()
        let data = encoder.encode(buffer)
        XCTAssertEqual(data.count, 4)
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Int(Int16(littleEndian: values[0])), 4_095, accuracy: 1)
    }
}
