@testable import MeetingAudioCapture
import Foundation
import XCTest

final class RecordingFilesTests: XCTestCase {
    func testCreatesPrivateSessionWithoutVisibleOutput() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "output", directoryHint: .isDirectory)
        let temporary = root.appending(path: "temporary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T04:01:02Z"))

        let files = try RecordingFiles.create(
            in: output,
            temporaryRoot: temporary,
            now: now,
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600)),
            id: "ABCD"
        )

        XCTAssertEqual(
            files.sessionDirectory,
            temporary.appending(path: "MeetingAudioCapture/ABCD", directoryHint: .isDirectory)
        )
        XCTAssertEqual(files.filenameStem, "Meeting-20260630-120102")
        XCTAssertEqual(files.systemTemporaryCAF.lastPathComponent, "system.caf")
        XCTAssertEqual(files.microphoneTemporaryCAF.lastPathComponent, "microphone.caf")
        XCTAssertEqual(files.temporaryM4A.lastPathComponent, "output.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.sessionDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
    }

    func testChoosesNextAvailableOutputName() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "output", directoryHint: .isDirectory)
        let temporary = root.appending(path: "temporary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try RecordingFiles.create(in: output, temporaryRoot: temporary, id: "TEST")

        XCTAssertEqual(files.nextOutputURL().lastPathComponent, "\(files.filenameStem).m4a")
        FileManager.default.createFile(
            atPath: output.appending(path: "\(files.filenameStem).m4a").path,
            contents: Data()
        )
        XCTAssertEqual(files.nextOutputURL().lastPathComponent, "\(files.filenameStem)-2.m4a")
        FileManager.default.createFile(
            atPath: output.appending(path: "\(files.filenameStem)-2.m4a").path,
            contents: Data()
        )
        XCTAssertEqual(files.nextOutputURL().lastPathComponent, "\(files.filenameStem)-3.m4a")
    }

    func testStaleCleanupRemovesOnlyApplicationOwnedSessions() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appending(path: "MeetingAudioCapture", directoryHint: .isDirectory)
        let stale = container.appending(path: "STALE", directoryHint: .isDirectory)
        let unrelated = root.appending(path: "OtherApp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        try RecordingFiles.removeStaleSessions(temporaryRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: container.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
