import AVFoundation

protocol MicrophonePermissionProviding: Sendable {
    func requestPermission() async -> Bool
}

struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
