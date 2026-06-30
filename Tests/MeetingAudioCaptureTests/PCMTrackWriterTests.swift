@testable import MeetingAudioCapture
import AVFAudio
import Foundation
import XCTest

final class PCMTrackWriterTests: XCTestCase {
    func testInsertsSilenceBeforeNextBuffer() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "track.caf")
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)
        )
        let first = try buffer(format: format, frames: 4_800, value: 0.5)
        let second = try buffer(format: format, frames: 4_800, value: 0.25)
        let writer = try PCMTrackWriter(url: url, format: format)

        try writer.append(first, atFrame: 0)
        try writer.append(second, atFrame: 9_600)
        try writer.finish()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 14_400)
        let contents = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 14_400))
        try file.read(into: contents)
        let samples = try XCTUnwrap(contents.floatChannelData?[0])
        XCTAssertEqual(samples[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[4_799], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[4_800], 0, accuracy: 0.0001)
        XCTAssertEqual(samples[9_599], 0, accuracy: 0.0001)
        XCTAssertEqual(samples[9_600], 0.25, accuracy: 0.0001)
    }

    private func buffer(format: AVAudioFormat, frames: AVAudioFrameCount, value: Float) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = Int(format.channelCount)
        for channel in 0..<channels {
            let data = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) {
                data[frame] = value
            }
        }
        return buffer
    }
}
