import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenCaptureClient: NSObject, CaptureClient, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let systemQueue = DispatchQueue(label: "org.meetingaudiocapture.system-audio")
    private let microphoneQueue = DispatchQueue(label: "org.meetingaudiocapture.microphone")
    private var continuation: AsyncThrowingStream<CaptureEvent, Error>.Continuation?
    private var captureStream: SCStream?
    private var acceptsSamples = false
    private var didStop = false
    private let permissionProvider: any MicrophonePermissionProviding
    private lazy var legacyMicrophone = LegacyMicrophoneCapture { [weak self] sampleBuffer in
        self?.yield(sampleBuffer, track: .microphone)
    }

    init(permissionProvider: any MicrophonePermissionProviding = SystemMicrophonePermissionProvider()) {
        self.permissionProvider = permissionProvider
    }

    func events() -> AsyncThrowingStream<CaptureEvent, Error> {
        AsyncThrowingStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
            }
        }
    }

    func start(microphoneDeviceID: String?) async throws {
        guard await permissionProvider.requestPermission() else {
            throw CaptureFailure.permissionDenied
        }

        do {
            let strategy = CaptureCapabilities.microphoneStrategy(
                for: ProcessInfo.processInfo.operatingSystemVersion
            )
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw CaptureFailure.noDisplayAvailable
            }
            let currentApplication = content.applications.first {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: currentApplication.map { [$0] } ?? [],
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            if #available(macOS 15.0, *), strategy == .screenCaptureKit {
                configuration.captureMicrophone = true
                configuration.microphoneCaptureDeviceID = microphoneDeviceID
            }
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: systemQueue)
            if #available(macOS 15.0, *), strategy == .screenCaptureKit {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneQueue)
            }
            lock.withLock {
                captureStream = stream
                acceptsSamples = true
                didStop = false
            }
            try await stream.startCapture()
            if strategy == .avCaptureSession {
                do {
                    try await legacyMicrophone.start(deviceID: microphoneDeviceID)
                } catch {
                    try? await stream.stopCapture()
                    lock.withLock {
                        captureStream = nil
                        acceptsSamples = false
                    }
                    throw error
                }
            }
        } catch let failure as CaptureFailure {
            throw failure
        } catch {
            throw CaptureFailure.setupFailed(error.localizedDescription)
        }
    }

    func pause() async {
        lock.withLock { acceptsSamples = false }
    }

    func resume() async {
        lock.withLock { acceptsSamples = true }
    }

    func stop() async {
        let state = lock.withLock { () -> (SCStream?, AsyncThrowingStream<CaptureEvent, Error>.Continuation?) in
            guard !didStop else { return (nil, nil) }
            didStop = true
            acceptsSamples = false
            let stream = captureStream
            captureStream = nil
            return (stream, continuation)
        }
        if let stream = state.0 {
            try? await stream.stopCapture()
        }
        await legacyMicrophone.stop()
        state.1?.finish()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        if outputType == .audio {
            yield(sampleBuffer, track: .system)
        } else if #available(macOS 15.0, *), outputType == .microphone {
            yield(sampleBuffer, track: .microphone)
        }
    }

    private func yield(_ sampleBuffer: CMSampleBuffer, track: CaptureTrack) {
        guard sampleBuffer.isValid else { return }
        let state = lock.withLock { () -> (Bool, AsyncThrowingStream<CaptureEvent, Error>.Continuation?) in
            (acceptsSamples, continuation)
        }
        guard state.0 else { return }
        state.1?.yield(.sample(track: track, buffer: sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let continuation = lock.withLock {
            acceptsSamples = false
            return self.continuation
        }
        continuation?.yield(.stopped(reason: error.localizedDescription))
        continuation?.finish()
        Task { await legacyMicrophone.stop() }
    }
}
