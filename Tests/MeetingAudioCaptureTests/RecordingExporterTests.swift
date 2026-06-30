@testable import MeetingAudioCapture
import AVFoundation
import Foundation
import XCTest

final class RecordingExporterTests: XCTestCase {
    func testExportsOneMP4WithDefaultMixAndIndependentTracks() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "output", directoryHint: .isDirectory)
        let temporary = root.appending(path: "temporary", directoryHint: .isDirectory)
        let files = try RecordingFiles.create(in: output, temporaryRoot: temporary, id: "TEST")
        try writeFixture(to: files.systemTemporaryCAF, channels: 2, value: 0.1)
        try writeFixture(to: files.microphoneTemporaryCAF, channels: 1, value: 0.2)

        let outputURL = try await RecordingExporter().export(files: files)

        XCTAssertEqual(outputURL.pathExtension, "mp4")
        XCTAssertEqual(outputURL.deletingLastPathComponent(), output)
        XCTAssertGreaterThan(try fileSize(outputURL), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [outputURL.lastPathComponent])

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 3)
        let descriptions = try await trackDescriptions(tracks)
        XCTAssertEqual(Set(descriptions.map(\.title)), ["Mixed", "System Audio", "Microphone"])
        XCTAssertEqual(descriptions.filter(\.enabled).map(\.title), ["Mixed"])
        for track in tracks {
            let timeRange = try await track.load(.timeRange)
            XCTAssertEqual(CMTimeGetSeconds(timeRange.duration), 1, accuracy: 0.05)
        }
    }

    func testFailureLeavesSessionForCleanupAndNoVisibleOutput() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "output", directoryHint: .isDirectory)
        let temporary = root.appending(path: "temporary", directoryHint: .isDirectory)
        let files = try RecordingFiles.create(in: output, temporaryRoot: temporary, id: "FAIL")
        try writeFixture(to: files.systemTemporaryCAF, channels: 2, value: 0.1)

        do {
            _ = try await RecordingExporter().export(files: files)
            XCTFail("Expected export to fail without microphone input")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        }
    }

    private func trackDescriptions(
        _ tracks: [AVAssetTrack]
    ) async throws -> [(title: String, enabled: Bool)] {
        var descriptions: [(String, Bool)] = []
        for track in tracks {
            let metadata = try await track.load(.commonMetadata)
            let titleItem = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .commonIdentifierTitle
            ).first
            let title = try await titleItem?.load(.stringValue)
            descriptions.append((try XCTUnwrap(title), try await track.load(.isEnabled)))
        }
        return descriptions
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFixture(to url: URL, channels: AVAudioChannelCount, value: Float) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: channels,
                interleaved: false
            )
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
