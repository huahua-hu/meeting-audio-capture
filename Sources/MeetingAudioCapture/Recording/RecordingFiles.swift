import Foundation

struct RecordingFiles: Equatable, Sendable {
    let directory: URL
    let systemTemporaryCAF: URL
    let microphoneTemporaryCAF: URL
    let systemM4A: URL
    let microphoneM4A: URL
    let mixedM4A: URL
    let metadataJSON: URL

    static func create(
        in root: URL,
        now: Date = .now,
        id: String = String(UUID().uuidString.prefix(4))
    ) throws -> RecordingFiles {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let directory = root.appending(
            path: "Recording-\(formatter.string(from: now))-\(id)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )

        return RecordingFiles(
            directory: directory,
            systemTemporaryCAF: directory.appending(path: ".system.caf"),
            microphoneTemporaryCAF: directory.appending(path: ".microphone.caf"),
            systemM4A: directory.appending(path: "system.m4a"),
            microphoneM4A: directory.appending(path: "microphone.m4a"),
            mixedM4A: directory.appending(path: "mixed.m4a"),
            metadataJSON: directory.appending(path: "metadata.json")
        )
    }
}

struct RecordingMetadata: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case completed
        case partial
        case failed
    }

    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let osVersion: String
    let appVersion: String
    let microphoneName: String
    let status: Status
    let error: String?
}
