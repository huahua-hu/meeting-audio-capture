import AVFAudio
import Foundation

enum TranscriptionTrackSource: Equatable, Sendable {
    case diagnostics
    case stereoExport(URL)
}

struct TranscriptionSession: Equatable, Sendable {
    let outputFile: URL
    let recordingName: String
    let diagnosticsDirectory: URL
    let systemAudioFile: URL
    let microphoneAudioFile: URL
    var trackSource: TranscriptionTrackSource = .diagnostics

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

    static func resolveSelectedAudio(
        outputFile: URL,
        fileManager: FileManager = .default
    ) throws -> TranscriptionSession {
        if let diagnosticsSession = try? resolve(outputFile: outputFile, fileManager: fileManager) {
            return diagnosticsSession
        }

        guard outputFile.pathExtension.lowercased() == "m4a" else {
            throw TranscriptionError.unsupportedAudio("Select an M4A exported by MeetingAudioCapture.")
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: outputFile)
        } catch {
            throw TranscriptionError.unsupportedAudio(error.localizedDescription)
        }
        guard audioFile.processingFormat.channelCount == 2 else {
            throw TranscriptionError.unsupportedAudio("The recording must contain two audio channels.")
        }

        let recordingName = outputFile.deletingPathExtension().lastPathComponent
        let diagnosticsDirectory = outputFile
            .deletingLastPathComponent()
            .appending(path: ".diagnostics/\(recordingName)", directoryHint: .isDirectory)
        return TranscriptionSession(
            outputFile: outputFile,
            recordingName: recordingName,
            diagnosticsDirectory: diagnosticsDirectory,
            systemAudioFile: outputFile,
            microphoneAudioFile: outputFile,
            trackSource: .stereoExport(outputFile)
        )
    }
}
