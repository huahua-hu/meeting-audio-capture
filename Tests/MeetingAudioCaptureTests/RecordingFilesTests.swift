@testable import MeetingAudioCapture
import Foundation
import XCTest

final class RecordingFilesTests: XCTestCase {
    func testCreatesUniqueSessionLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T04:01:02Z"))

        let files = try RecordingFiles.create(in: root, now: now, id: "ABCD")

        XCTAssertEqual(files.directory.lastPathComponent, "Recording-20260630-120102-ABCD")
        XCTAssertEqual(files.systemM4A.lastPathComponent, "system.m4a")
        XCTAssertEqual(files.microphoneM4A.lastPathComponent, "microphone.m4a")
        XCTAssertEqual(files.mixedM4A.lastPathComponent, "mixed.m4a")
        XCTAssertEqual(files.metadataJSON.lastPathComponent, "metadata.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.directory.path))
    }

    func testMetadataRoundTrips() throws {
        let start = Date(timeIntervalSince1970: 100)
        let metadata = RecordingMetadata(
            startedAt: start,
            endedAt: start.addingTimeInterval(62.5),
            durationSeconds: 62.5,
            osVersion: "15.5",
            appVersion: "0.1.0",
            microphoneName: "MacBook Microphone",
            status: .partial,
            error: "mix failed"
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(RecordingMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
    }
}
