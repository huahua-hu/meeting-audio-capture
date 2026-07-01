import AVFoundation
import CoreMedia
import Foundation

final class LegacyMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias SampleHandler = @Sendable (CMSampleBuffer) -> Void

    private let queue = DispatchQueue(label: "org.meetingaudiocapture.legacy-microphone")
    private let sampleHandler: SampleHandler
    private var session: AVCaptureSession?

    init(sampleHandler: @escaping SampleHandler) {
        self.sampleHandler = sampleHandler
    }

    func start(deviceID: String?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let devices = AVCaptureDevice.devices(for: .audio)
                    let selectedID = Self.resolveDeviceID(
                        requested: deviceID,
                        availableIDs: devices.map(\.uniqueID),
                        defaultID: AVCaptureDevice.default(for: .audio)?.uniqueID
                    )
                    guard let selectedID,
                          let device = devices.first(where: { $0.uniqueID == selectedID }) else {
                        throw CaptureFailure.setupFailed("No microphone is available.")
                    }

                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw CaptureFailure.setupFailed("The selected microphone cannot be captured.")
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    session.commitConfiguration()
                    session.startRunning()
                    self.session = session
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session?.stopRunning()
                self.session = nil
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        sampleHandler(sampleBuffer)
    }

    static func resolveDeviceID(
        requested: String?,
        availableIDs: [String],
        defaultID: String?
    ) -> String? {
        if let requested, availableIDs.contains(requested) {
            return requested
        }
        if let defaultID, availableIDs.contains(defaultID) {
            return defaultID
        }
        return availableIDs.first
    }
}
