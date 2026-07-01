@testable import MeetingAudioCapture
import AVFAudio
import AVFoundation
import Foundation
import XCTest

final class RecordingExporterTests: XCTestCase {
    private enum CleanupFailure: Error { case expected }

    func testExportsOneStereoM4AAndRemovesSession() async throws {
        let (root, files) = try makeFiles(id: "SUCCESS")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFixture(to: files.systemTemporaryCAF, channels: 2)
        try writeFixture(to: files.microphoneTemporaryCAF, channels: 1)

        let output = try await RecordingExporter().export(files: files)

        XCTAssertEqual(output.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.outputDirectory.path), [output.lastPathComponent])
        let audio = try AVAudioFile(forReading: output)
        XCTAssertEqual(audio.fileFormat.channelCount, 2)
        XCTAssertEqual(audio.fileFormat.sampleRate, 48_000, accuracy: 0.1)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
    }

    func testFailureLeavesSessionAndNoVisibleOutput() async throws {
        let (root, files) = try makeFiles(id: "FAIL")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFixture(to: files.systemTemporaryCAF, channels: 2)

        do {
            _ = try await RecordingExporter().export(files: files)
            XCTFail("Expected missing microphone source to fail")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: files.outputDirectory.path), [])
        }
    }

    func testCleanupFailureDoesNotDeleteCompletedM4A() async throws {
        let (root, files) = try makeFiles(id: "CLEANUP")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFixture(to: files.systemTemporaryCAF, channels: 2)
        try writeFixture(to: files.microphoneTemporaryCAF, channels: 1)
        let exporter = RecordingExporter(removeSession: { _ in throw CleanupFailure.expected })

        let output = try await exporter.export(files: files)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
    }

    private func makeFiles(id: String) throws -> (URL, RecordingFiles) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let output = root.appending(path: "output", directoryHint: .isDirectory)
        let temporary = root.appending(path: "temporary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, try RecordingFiles.create(in: output, temporaryRoot: temporary, id: id))
    }

    private func writeFixture(to url: URL, channels: AVAudioChannelCount) throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: false))
        let writer = try PCMTrackWriter(url: url, format: format)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        for channel in 0..<Int(channels) {
            let samples = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<4_800 { samples[frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000)) * 0.2 }
        }
        try writer.append(buffer, atFrame: 0)
        try writer.finish()
    }
}
