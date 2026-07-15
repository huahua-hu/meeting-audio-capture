import AVFoundation
import CoreMedia
import Foundation

final class LegacyMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias SampleHandler = @Sendable (CMSampleBuffer) -> Void
    typealias SessionFactory = @Sendable (String?, LegacyMicrophoneCapture) throws -> AVCaptureSession
    typealias SessionOperation = @Sendable (AVCaptureSession) -> Void

    private let queue = DispatchQueue(label: "org.meetingaudiocapture.legacy-microphone")
    private let sampleHandler: SampleHandler
    private let sessionFactory: SessionFactory
    private let startSession: SessionOperation
    private let stopSession: SessionOperation
    private var session: AVCaptureSession?

    init(
        sampleHandler: @escaping SampleHandler,
        sessionFactory: SessionFactory? = nil,
        startSession: @escaping SessionOperation = { $0.startRunning() },
        stopSession: @escaping SessionOperation = { $0.stopRunning() }
    ) {
        self.sampleHandler = sampleHandler
        self.sessionFactory = sessionFactory ?? { deviceID, capture in
            try capture.makeSession(deviceID: deviceID)
        }
        self.startSession = startSession
        self.stopSession = stopSession
    }

    func start(deviceID: String?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let session = try self.sessionFactory(deviceID, self)
                    self.startSession(session)
                    self.session = session
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func switchDevice(to deviceID: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let replacement = try self.sessionFactory(deviceID, self)
                    if let session = self.session {
                        self.stopSession(session)
                    }
                    self.startSession(replacement)
                    self.session = replacement
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
                if let session = self.session {
                    self.stopSession(session)
                }
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

    private func makeSession(deviceID: String?) throws -> AVCaptureSession {
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
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        return session
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
