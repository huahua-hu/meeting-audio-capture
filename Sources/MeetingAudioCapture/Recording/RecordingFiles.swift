import Foundation

struct RecordingFiles: Equatable, Sendable {
    private static let temporaryContainerName = "MeetingAudioCapture"

    let sessionDirectory: URL
    let systemTemporaryCAF: URL
    let microphoneTemporaryCAF: URL
    let temporaryM4A: URL
    let outputDirectory: URL
    let filenameStem: String

    static func create(
        in outputDirectory: URL,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        now: Date = .now,
        timeZone: TimeZone = .current,
        id: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) throws -> RecordingFiles {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let container = temporaryRoot.appending(
            path: temporaryContainerName,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        let sessionDirectory = container.appending(path: id, directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: false
        )

        return RecordingFiles(
            sessionDirectory: sessionDirectory,
            systemTemporaryCAF: sessionDirectory.appending(path: "system.caf"),
            microphoneTemporaryCAF: sessionDirectory.appending(path: "microphone.caf"),
            temporaryM4A: sessionDirectory.appending(path: "output.m4a"),
            outputDirectory: outputDirectory,
            filenameStem: "Meeting-\(formatter.string(from: now))"
        )
    }

    func nextOutputURL(fileManager: FileManager = .default) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? filenameStem : "\(filenameStem)-\(suffix)"
            let candidate = outputDirectory.appending(path: "\(name).m4a")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    func removeTemporarySession(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: sessionDirectory.path) {
            try fileManager.removeItem(at: sessionDirectory)
        }
    }

    static func removeStaleSessions(
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws {
        let container = temporaryRoot.appending(
            path: temporaryContainerName,
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: container.path) {
            try fileManager.removeItem(at: container)
        }
    }
}
