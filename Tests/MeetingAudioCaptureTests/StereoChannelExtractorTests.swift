@testable import MeetingAudioCapture
import AVFAudio
import XCTest

final class StereoChannelExtractorTests: XCTestCase {
    func testExtractsLeftAndRightChannelsIntoTimedChunks() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.m4a")
        try writeStereo(to: source, frames: 9_600)

        let tracks = try StereoChannelExtractor().extract(url: source, chunkDuration: 0.1)
        defer { tracks.cleanup() }

        XCTAssertEqual(tracks.chunks.count, 2)
        XCTAssertEqual(tracks.chunks.map(\.startTime), [0, 0.1])
        let first = try XCTUnwrap(tracks.chunks.first)
        XCTAssertEqual(first.systemAudioFile.pathExtension, "caf")
        XCTAssertEqual(
            try AVAudioFile(forReading: first.systemAudioFile).fileFormat.settings[AVFormatIDKey] as? UInt32,
            kAudioFormatLinearPCM as UInt32
        )
        XCTAssertGreaterThan(try rms(first.systemAudioFile), 0.05)
        XCTAssertGreaterThan(try rms(first.microphoneAudioFile), 0.15)
        XCTAssertLessThan(try rms(first.systemAudioFile), try rms(first.microphoneAudioFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.systemAudioFile.path))

        tracks.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tracks.directory.path))
    }

    private func writeStereo(to url: URL, frames: AVAudioFrameCount) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let left = try XCTUnwrap(buffer.floatChannelData?[0])
        let right = try XCTUnwrap(buffer.floatChannelData?[1])
        for frame in 0..<Int(frames) {
            left[frame] = 0.1
            right[frame] = 0.3
        }
        try file.write(from: buffer)
    }

    private func rms(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let count = Int(buffer.frameLength)
        let sum = (0..<count).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) }
        return sqrt(sum / Double(count))
    }
}
