import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

protocol MicrophoneRouteControlling: AnyObject, Sendable {
    func defaultDeviceDidChange(to deviceID: String?) async
    func stop() async
}

extension MicrophoneRouteController: MicrophoneRouteControlling {}

final class MicrophoneRoutingSession: @unchecked Sendable {
    private let requestedDeviceID: String?
    private let monitor: any DefaultInputDeviceMonitoring
    private let routeController: any MicrophoneRouteControlling

    init(
        requestedDeviceID: String?,
        monitor: any DefaultInputDeviceMonitoring,
        routeController: any MicrophoneRouteControlling
    ) {
        self.requestedDeviceID = requestedDeviceID
        self.monitor = monitor
        self.routeController = routeController
    }

    func start() {
        guard requestedDeviceID == nil else { return }

        do {
            try monitor.start { [weak routeController] deviceID in
                guard let routeController else { return }
                Task { await routeController.defaultDeviceDidChange(to: deviceID) }
            }
            let currentDeviceID = monitor.currentDeviceID()
            Task { [weak routeController] in
                await routeController?.defaultDeviceDidChange(to: currentDeviceID)
            }
        } catch {
            monitor.stop()
        }
    }

    func stop() async {
        monitor.stop()
        await routeController.stop()
    }
}

final class ScreenCaptureClient: NSObject, CaptureClient, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let systemQueue = DispatchQueue(label: "org.meetingaudiocapture.system-audio")
    private let microphoneQueue = DispatchQueue(label: "org.meetingaudiocapture.microphone")
    private var continuation: AsyncThrowingStream<CaptureEvent, Error>.Continuation?
    private var captureStream: SCStream?
    private var microphoneRouting: MicrophoneRoutingSession?
    private var acceptsSamples = false
    private var didStop = false
    private let permissionProvider: any MicrophonePermissionProviding
    private let defaultInputMonitor: any DefaultInputDeviceMonitoring
    private lazy var legacyMicrophone = LegacyMicrophoneCapture { [weak self] sampleBuffer in
        self?.yield(sampleBuffer, track: .microphone)
    }

    init(
        permissionProvider: any MicrophonePermissionProviding = SystemMicrophonePermissionProvider(),
        defaultInputMonitor: any DefaultInputDeviceMonitoring = SystemDefaultInputDeviceMonitor()
    ) {
        self.permissionProvider = permissionProvider
        self.defaultInputMonitor = defaultInputMonitor
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
            let effectiveMicrophoneID = Self.effectiveMicrophoneID(
                requestedDeviceID: microphoneDeviceID,
                currentDefaultDeviceID: defaultInputMonitor.currentDeviceID()
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
            let configuration = Self.makeConfiguration(
                strategy: strategy,
                microphoneDeviceID: effectiveMicrophoneID
            )

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
                    try await legacyMicrophone.start(deviceID: effectiveMicrophoneID)
                } catch {
                    try? await stream.stopCapture()
                    lock.withLock {
                        captureStream = nil
                        acceptsSamples = false
                    }
                    throw error
                }
            }

            let routeController = MicrophoneRouteController(
                requestedDeviceID: microphoneDeviceID,
                initialDefaultDeviceID: effectiveMicrophoneID
            ) { [weak self] deviceID in
                guard let self else { return }
                try await self.switchMicrophone(to: deviceID, strategy: strategy)
            }
            let routing = MicrophoneRoutingSession(
                requestedDeviceID: microphoneDeviceID,
                monitor: defaultInputMonitor,
                routeController: routeController
            )
            lock.withLock { microphoneRouting = routing }
            routing.start()
        } catch let failure as CaptureFailure {
            await cleanUpFailedStart()
            throw failure
        } catch {
            await cleanUpFailedStart()
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
        let state = lock.withLock { () -> (
            SCStream?,
            MicrophoneRoutingSession?,
            AsyncThrowingStream<CaptureEvent, Error>.Continuation?
        ) in
            guard !didStop else { return (nil, nil, nil) }
            didStop = true
            acceptsSamples = false
            let stream = captureStream
            captureStream = nil
            let routing = microphoneRouting
            microphoneRouting = nil
            return (stream, routing, continuation)
        }
        await state.1?.stop()
        if let stream = state.0 {
            try? await stream.stopCapture()
        }
        await legacyMicrophone.stop()
        state.2?.finish()
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
        let state = lock.withLock { () -> (
            MicrophoneRoutingSession?,
            AsyncThrowingStream<CaptureEvent, Error>.Continuation?
        ) in
            guard !didStop else { return (nil, nil) }
            didStop = true
            acceptsSamples = false
            captureStream = nil
            let routing = microphoneRouting
            microphoneRouting = nil
            return (routing, continuation)
        }
        Task {
            await state.0?.stop()
            await legacyMicrophone.stop()
            state.1?.yield(.stopped(reason: error.localizedDescription))
            state.1?.finish()
        }
    }

    static func effectiveMicrophoneID(
        requestedDeviceID: String?,
        currentDefaultDeviceID: String?
    ) -> String? {
        requestedDeviceID ?? currentDefaultDeviceID
    }

    static func makeConfiguration(
        strategy: MicrophoneCaptureStrategy,
        microphoneDeviceID: String?
    ) -> SCStreamConfiguration {
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
        return configuration
    }

    private func switchMicrophone(
        to deviceID: String,
        strategy: MicrophoneCaptureStrategy
    ) async throws {
        switch strategy {
        case .avCaptureSession:
            try await legacyMicrophone.switchDevice(to: deviceID)
        case .screenCaptureKit:
            guard #available(macOS 15.0, *) else {
                throw CaptureFailure.setupFailed("ScreenCaptureKit microphone switching requires macOS 15.")
            }
            guard let stream = lock.withLock({ didStop ? nil : captureStream }) else {
                throw CaptureFailure.setupFailed("The capture stream is no longer running.")
            }
            let configuration = Self.makeConfiguration(
                strategy: strategy,
                microphoneDeviceID: deviceID
            )
            try await stream.updateConfiguration(configuration)
        }
    }

    private func cleanUpFailedStart() async {
        let state = lock.withLock { () -> (SCStream?, MicrophoneRoutingSession?) in
            acceptsSamples = false
            let stream = captureStream
            captureStream = nil
            let routing = microphoneRouting
            microphoneRouting = nil
            return (stream, routing)
        }
        await state.1?.stop()
        if let stream = state.0 {
            try? await stream.stopCapture()
        }
        await legacyMicrophone.stop()
    }
}
