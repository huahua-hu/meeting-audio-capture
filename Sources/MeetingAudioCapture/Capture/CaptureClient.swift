import CoreMedia
import Foundation

enum CaptureTrack: Equatable, Sendable {
    case system
    case microphone
}

enum CaptureEvent: @unchecked Sendable {
    case sample(track: CaptureTrack, buffer: CMSampleBuffer)
    case stopped(reason: String?)
}

enum CaptureFailure: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case noDisplayAvailable
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Recording permission was denied. Enable MeetingAudioCapture in System Settings > Privacy & Security > Microphone and Screen & System Audio Recording."
        case .noDisplayAvailable:
            "No display is available for system audio capture."
        case let .setupFailed(message):
            "Unable to start audio capture: \(message)"
        }
    }
}

protocol CaptureClient: Sendable {
    func events() -> AsyncThrowingStream<CaptureEvent, Error>
    func start(microphoneDeviceID: String?) async throws
    func pause() async
    func resume() async
    func stop() async
}
