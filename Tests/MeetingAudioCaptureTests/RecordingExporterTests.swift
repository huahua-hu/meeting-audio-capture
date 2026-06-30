@testable import MeetingAudioCapture
import AVFoundation
import Foundation
import XCTest

final class RecordingExporterTests: XCTestCase {
    func testExportsIndependentTracksAndMix() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = try RecordingFiles.create(in: root, id: "TEST")
        try writeFixture(to: files.systemTemporaryCAF, channels: 2, value: 0.1)
        try writeFixture(to: files.microphoneTemporaryCAF, channels: 1, value: 0.2)

        let result = await RecordingExporter().export(files: files)

        XCTAssertTrue(result.systemSucceeded)
        XCTAssertTrue(result.microphoneSucceeded)
        XCTAssertTrue(result.mixSucceeded)
        for url in [files.systemM4A, files.microphoneM4A, files.mixedM4A] {
            XCTAssertGreaterThan(try fileSize(url), 0)
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(CMTimeGetSeconds(duration), 1, accuracy: 0.05)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertFalse(audioTracks.isEmpty)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.systemTemporaryCAF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.microphoneTemporaryCAF.path))
    }

    private func writeFixture(to url: URL, channels: AVAudioChannelCount, value: Float) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: false)
        )
        let writer = try PCMTrackWriter(url: url, format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for channel in 0..<Int(channels) {
            let data = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<48_000 { data[frame] = value }
        }
        try writer.append(buffer, atFrame: 0)
        try writer.finish()
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? Int)
    }
}
