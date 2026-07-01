@testable import MeetingAudioCapture
import AVFAudio
import XCTest

final class StereoM4AEncoderTests: XCTestCase {
    func testEncodesSystemOnLeftAndMicrophoneOnRight() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appending(path: "system.caf")
        let microphone = root.appending(path: "microphone.caf")
        let output = root.appending(path: "output.m4a")
        try writeSystem(to: system, frames: 48_000)
        try writeMicrophone(to: microphone, frames: 48_000)

        try StereoM4AEncoder().encode(systemCAF: system, microphoneCAF: microphone, destination: output)

        let decoded = try decode(output)
        XCTAssertEqual(decoded.format.channelCount, 2)
        XCTAssertEqual(decoded.format.sampleRate, 48_000, accuracy: 0.1)
        let left = try XCTUnwrap(decoded.floatChannelData?[0])
        let right = try XCTUnwrap(decoded.floatChannelData?[1])
        let count = Int(decoded.frameLength)
        XCTAssertGreaterThan(amplitude(left, count: count, frequency: 440), 0.20)
        XCTAssertLessThan(amplitude(left, count: count, frequency: 880), 0.03)
        XCTAssertGreaterThan(amplitude(right, count: count, frequency: 880), 0.35)
        XCTAssertLessThan(amplitude(right, count: count, frequency: 440), 0.03)
    }

    func testPadsShorterMicrophoneWithSilence() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appending(path: "system.caf")
        let microphone = root.appending(path: "microphone.caf")
        let output = root.appending(path: "output.m4a")
        try writeSystem(to: system, frames: 48_000)
        try writeMicrophone(to: microphone, frames: 24_000)

        try StereoM4AEncoder().encode(systemCAF: system, microphoneCAF: microphone, destination: output)

        let decoded = try decode(output)
        XCTAssertGreaterThanOrEqual(decoded.frameLength, 47_000)
        let left = try XCTUnwrap(decoded.floatChannelData?[0])
        let right = try XCTUnwrap(decoded.floatChannelData?[1])
        let start = Int(decoded.frameLength * 3 / 4)
        XCTAssertGreaterThan(rms(left, range: start..<Int(decoded.frameLength)), 0.10)
        XCTAssertLessThan(rms(right, range: start..<Int(decoded.frameLength)), 0.02)
    }

    private func writeSystem(to url: URL, frames: AVAudioFrameCount) throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let file = try PCMTrackWriter(url: url, format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let left = try XCTUnwrap(buffer.floatChannelData?[0])
        let right = try XCTUnwrap(buffer.floatChannelData?[1])
        for frame in 0..<Int(frames) {
            let sample = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000))
            left[frame] = sample * 0.2
            right[frame] = sample * 0.4
        }
        try file.append(buffer, atFrame: 0)
        try file.finish()
    }

    private func writeMicrophone(to url: URL, frames: AVAudioFrameCount) throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let file = try PCMTrackWriter(url: url, format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frames) {
            samples[frame] = Float(sin(2 * Double.pi * 880 * Double(frame) / 48_000)) * 0.5
        }
        try file.append(buffer, atFrame: 0)
        try file.finish()
    }

    private func decode(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity))
        try file.read(into: buffer)
        return buffer
    }

    private func amplitude(_ samples: UnsafePointer<Float>, count: Int, frequency: Double) -> Double {
        var sine = 0.0
        var cosine = 0.0
        for frame in 0..<count {
            let phase = 2 * Double.pi * frequency * Double(frame) / 48_000
            sine += Double(samples[frame]) * sin(phase)
            cosine += Double(samples[frame]) * cos(phase)
        }
        return 2 * hypot(sine, cosine) / Double(count)
    }

    private func rms(_ samples: UnsafePointer<Float>, range: Range<Int>) -> Double {
        let sum = range.reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) }
        return sqrt(sum / Double(range.count))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
