@preconcurrency import AVFoundation
import AVFAudio
import Foundation

protocol RecordingExporting: Sendable {
    func export(files: RecordingFiles) async throws -> URL
}

enum RecordingExportError: Error, LocalizedError, Sendable {
    case encodingFailed(String)
    case invalidOutput(String)
    case moveFailed

    var errorDescription: String? {
        switch self {
        case let .encodingFailed(details): "Unable to encode M4A: \(details)"
        case let .invalidOutput(details): "Invalid M4A output: \(details)"
        case .moveFailed: "Unable to move the completed M4A."
        }
    }
}

struct RecordingExporter: RecordingExporting, Sendable {
    private let encoder: StereoM4AEncoder
    private let preserveDiagnostics: @Sendable (RecordingFiles, URL) throws -> URL
    private let removeSession: @Sendable (RecordingFiles) throws -> Void

    init(
        encoder: StereoM4AEncoder = StereoM4AEncoder(),
        preserveDiagnostics: @escaping @Sendable (RecordingFiles, URL) throws -> URL = {
            try $0.preserveDiagnostics(for: $1)
        },
        removeSession: @escaping @Sendable (RecordingFiles) throws -> Void = {
            try $0.removeTemporarySession()
        }
    ) {
        self.encoder = encoder
        self.preserveDiagnostics = preserveDiagnostics
        self.removeSession = removeSession
    }

    func export(files: RecordingFiles) async throws -> URL {
        do {
            try encoder.encode(
                systemCAF: files.systemTemporaryCAF,
                microphoneCAF: files.microphoneTemporaryCAF,
                destination: files.temporaryM4A
            )
        } catch {
            throw RecordingExportError.encodingFailed(error.localizedDescription)
        }
        try await validate(url: files.temporaryM4A)

        let outputURL = files.nextOutputURL()
        do {
            try FileManager.default.moveItem(at: files.temporaryM4A, to: outputURL)
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw RecordingExportError.moveFailed
        }
        if let markdown = try? TranscriptJournal.renderMarkdown(
            from: files.transcriptJournalJSONL,
            sourceName: outputURL.lastPathComponent
        ), !markdown.isEmpty {
            let transcriptURL = outputURL.deletingPathExtension().appendingPathExtension("md")
            try? markdown.write(to: transcriptURL, atomically: true, encoding: .utf8)
        }
        _ = try preserveDiagnostics(files, outputURL)
        try? removeSession(files)
        return outputURL
    }

    private func validate(url: URL) async throws {
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        guard tracks.count == 1 else {
            throw RecordingExportError.invalidOutput("expected one audio track")
        }
        let file = try AVAudioFile(forReading: url)
        guard file.fileFormat.channelCount == 2 else {
            throw RecordingExportError.invalidOutput("expected stereo audio")
        }
        guard abs(file.fileFormat.sampleRate - 48_000) < 0.1 else {
            throw RecordingExportError.invalidOutput("expected 48 kHz audio")
        }
    }
}
