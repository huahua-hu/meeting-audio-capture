import Foundation

enum MicrophoneCaptureStrategy: Equatable, Sendable {
    case avCaptureSession
    case screenCaptureKit
}

enum CaptureCapabilities {
    static func microphoneStrategy(for version: OperatingSystemVersion) -> MicrophoneCaptureStrategy {
        version.majorVersion >= 15 ? .screenCaptureKit : .avCaptureSession
    }
}
