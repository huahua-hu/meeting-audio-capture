@testable import MeetingAudioCapture
import Foundation
import XCTest

final class TranscriptionSessionTests: XCTestCase {
    func testResolvesDiagnosticsTracksFromOutputFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        try Data("m4a".utf8).write(to: output)
        try Data("system".utf8).write(to: diagnostics.appending(path: "system.caf"))
        try Data("microphone".utf8).write(to: diagnostics.appending(path: "microphone.caf"))

        let session = try TranscriptionSession.resolve(outputFile: output)

        XCTAssertEqual(session.outputFile, output)
        XCTAssertEqual(session.recordingName, "Meeting-20260706-091500")
        XCTAssertEqual(session.diagnosticsDirectory, diagnostics)
        XCTAssertEqual(session.systemAudioFile, diagnostics.appending(path: "system.caf"))
        XCTAssertEqual(session.microphoneAudioFile, diagnostics.appending(path: "microphone.caf"))
    }

    func testThrowsWhenDiagnosticsDirectoryIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        try Data("m4a".utf8).write(to: output)

        XCTAssertThrowsError(try TranscriptionSession.resolve(outputFile: output)) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingDiagnostics)
        }
    }

    func testThrowsWhenTrackFileIsMissing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appending(path: "Meeting-20260706-091500.m4a")
        let diagnostics = root.appending(path: ".diagnostics/Meeting-20260706-091500", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        try Data("m4a".utf8).write(to: output)
        try Data("system".utf8).write(to: diagnostics.appending(path: "system.caf"))

        XCTAssertThrowsError(try TranscriptionSession.resolve(outputFile: output)) { error in
            XCTAssertEqual(error as? TranscriptionError, .missingTrack("microphone.caf"))
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
