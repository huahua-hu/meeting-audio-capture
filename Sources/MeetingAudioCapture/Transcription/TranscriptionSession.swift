import Foundation

struct TranscriptionSession: Equatable, Sendable {
    let outputFile: URL
    let recordingName: String
    let diagnosticsDirectory: URL
    let systemAudioFile: URL
    let microphoneAudioFile: URL

    static func resolve(
        outputFile: URL,
        fileManager: FileManager = .default
    ) throws -> TranscriptionSession {
        let recordingName = outputFile.deletingPathExtension().lastPathComponent
        let diagnosticsDirectory = outputFile
            .deletingLastPathComponent()
            .appending(path: ".diagnostics/\(recordingName)", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: diagnosticsDirectory.path) else {
            throw TranscriptionError.missingDiagnostics
        }

        let systemAudioFile = diagnosticsDirectory.appending(path: "system.caf")
        guard fileManager.fileExists(atPath: systemAudioFile.path) else {
            throw TranscriptionError.missingTrack("system.caf")
        }

        let microphoneAudioFile = diagnosticsDirectory.appending(path: "microphone.caf")
        guard fileManager.fileExists(atPath: microphoneAudioFile.path) else {
            throw TranscriptionError.missingTrack("microphone.caf")
        }

        return TranscriptionSession(
            outputFile: outputFile,
            recordingName: recordingName,
            diagnosticsDirectory: diagnosticsDirectory,
            systemAudioFile: systemAudioFile,
            microphoneAudioFile: microphoneAudioFile
        )
    }
}
