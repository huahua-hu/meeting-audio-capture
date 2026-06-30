import AVFAudio
import CoreMedia
import Foundation

struct RecordingSnapshot: Equatable, Sendable {
    let state: RecordingState
    let elapsedSeconds: Double
    let systemLevel: AudioLevel
    let microphoneLevel: AudioLevel
    let outputDirectory: URL?
}

actor RecordingCoordinator {
    typealias CapacityProvider = @Sendable (URL) -> Int64

    private let capture: any CaptureClient
    private let exporter: RecordingExporter
    private let availableCapacity: CapacityProvider
    private var stateMachine = RecordingStateMachine()
    private var snapshot = RecordingSnapshot(
        state: .idle,
        elapsedSeconds: 0,
        systemLevel: .silence,
        microphoneLevel: .silence,
        outputDirectory: nil
    )
    private var snapshotContinuation: AsyncStream<RecordingSnapshot>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var files: RecordingFiles?
    private var startedAt: Date?
    private var microphoneName = ""
    private var pendingSamples: [(CaptureTrack, CMSampleBuffer)] = []
    private var firstPTS: [CaptureTrack: CMTime] = [:]
    private var timeline: FrameTimeline?
    private var systemWriter: PCMTrackWriter?
    private var microphoneWriter: PCMTrackWriter?
    private var lastPresentationTime = CMTime.zero
    private var maxWrittenFrames: AVAudioFramePosition = 0
    private var isFinalizing = false

    init(
        capture: any CaptureClient,
        exporter: RecordingExporter = .init(),
        availableCapacity: @escaping CapacityProvider = RecordingCoordinator.defaultAvailableCapacity
    ) {
        self.capture = capture
        self.exporter = exporter
        self.availableCapacity = availableCapacity
    }

    func currentSnapshot() -> RecordingSnapshot { snapshot }

    func snapshots() -> AsyncStream<RecordingSnapshot> {
        let initial = snapshot
        return AsyncStream { continuation in
            continuation.yield(initial)
            self.storeSnapshotContinuation(continuation)
        }
    }

    func start(
        root: URL,
        microphoneDeviceID: String?,
        microphoneName: String
    ) async throws {
        if case .completed = stateMachine.state { try stateMachine.transition(to: .idle) }
        if case .failed = stateMachine.state { try stateMachine.transition(to: .idle) }
        guard availableCapacity(root) >= 500_000_000 else {
            throw RecordingFailure(message: "At least 500 MB of free space is required.")
        }

        try stateMachine.transition(to: .preparing)
        let files = try RecordingFiles.create(in: root)
        self.files = files
        self.startedAt = .now
        self.microphoneName = microphoneName
        pendingSamples.removeAll(keepingCapacity: true)
        firstPTS.removeAll(keepingCapacity: true)
        timeline = nil
        systemWriter = nil
        microphoneWriter = nil
        maxWrittenFrames = 0
        lastPresentationTime = .zero
        publish(state: .preparing)

        let events = capture.events()
        eventTask = Task { [weak self] in
            do {
                for try await event in events {
                    await self?.handle(event)
                }
            } catch {
                await self?.fail(with: error.localizedDescription)
            }
        }

        do {
            try await capture.start(microphoneDeviceID: microphoneDeviceID)
        } catch {
            await fail(with: error.localizedDescription)
            throw error
        }
    }

    func pause() async throws {
        guard stateMachine.state == .recording else {
            throw InvalidStateTransition(from: stateMachine.state, to: .paused)
        }
        try timeline?.beginPause(at: currentCaptureTime())
        await capture.pause()
        try stateMachine.transition(to: .paused)
        publish(state: .paused)
    }

    func resume() async throws {
        guard stateMachine.state == .paused else {
            throw InvalidStateTransition(from: stateMachine.state, to: .recording)
        }
        try timeline?.endPause(at: currentCaptureTime())
        await capture.resume()
        try stateMachine.transition(to: .recording)
        publish(state: .recording)
    }

    func stop() async {
        guard stateMachine.state == .recording || stateMachine.state == .paused,
              !isFinalizing else { return }
        isFinalizing = true
        try? stateMachine.transition(to: .stopping)
        publish(state: .stopping)
        await capture.stop()
        eventTask?.cancel()
        eventTask = nil
        await finalize(error: nil)
        isFinalizing = false
    }

    private func handle(_ event: CaptureEvent) async {
        switch event {
        case let .sample(track, buffer):
            do {
                try handleSample(track: track, buffer: buffer)
            } catch {
                await fail(with: error.localizedDescription)
            }
        case let .stopped(reason):
            await fail(with: reason ?? "Audio capture stopped unexpectedly.")
        }
    }

    private func handleSample(track: CaptureTrack, buffer: CMSampleBuffer) throws {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        lastPresentationTime = max(lastPresentationTime, pts)
        if timeline == nil {
            pendingSamples.append((track, buffer))
            firstPTS[track] = firstPTS[track] ?? pts
            guard let systemPTS = firstPTS[.system],
                  let microphonePTS = firstPTS[.microphone],
                  let files else { return }
            let origin = min(systemPTS, microphonePTS)
            timeline = FrameTimeline(sampleRate: 48_000, origin: origin)
            let systemFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )!
            let microphoneFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )!
            systemWriter = try PCMTrackWriter(url: files.systemTemporaryCAF, format: systemFormat)
            microphoneWriter = try PCMTrackWriter(url: files.microphoneTemporaryCAF, format: microphoneFormat)
            let buffered = pendingSamples.sorted {
                CMSampleBufferGetPresentationTimeStamp($0.1) < CMSampleBufferGetPresentationTimeStamp($1.1)
            }
            pendingSamples.removeAll(keepingCapacity: false)
            for (bufferedTrack, bufferedSample) in buffered {
                try write(track: bufferedTrack, buffer: bufferedSample)
            }
            try stateMachine.transition(to: .recording)
            publish(state: .recording)
            return
        }
        try write(track: track, buffer: buffer)
    }

    private func write(track: CaptureTrack, buffer: CMSampleBuffer) throws {
        guard let timeline else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let targetFrame = timeline.frameIndex(for: pts)
        switch track {
        case .system:
            guard let writer = systemWriter else { return }
            let pcm = try AudioSampleDecoder.decode(buffer, targetFormat: writer.format)
            try writer.append(pcm, atFrame: targetFrame)
            maxWrittenFrames = max(maxWrittenFrames, writer.writtenFrameCount)
            publish(level: level(from: pcm), for: .system)
        case .microphone:
            guard let writer = microphoneWriter else { return }
            let pcm = try AudioSampleDecoder.decode(buffer, targetFormat: writer.format)
            try writer.append(pcm, atFrame: targetFrame)
            maxWrittenFrames = max(maxWrittenFrames, writer.writtenFrameCount)
            publish(level: level(from: pcm), for: .microphone)
        }
    }

    private func level(from buffer: AVAudioPCMBuffer) -> AudioLevel {
        guard let channel = buffer.floatChannelData?[0] else { return .silence }
        return AudioLevelMeter.measure(
            UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        )
    }

    private func fail(with message: String) async {
        guard !isFinalizing else { return }
        isFinalizing = true
        await capture.stop()
        try? stateMachine.transition(to: .failed(.init(message: message)))
        publish(state: stateMachine.state)
        await finalize(error: message)
        isFinalizing = false
    }

    private func finalize(error: String?) async {
        try? systemWriter?.finish()
        try? microphoneWriter?.finish()
        systemWriter = nil
        microphoneWriter = nil
        guard let files, let startedAt else { return }
        let exportResult = await exporter.export(files: files)
        let allSucceeded = exportResult.systemSucceeded
            && exportResult.microphoneSucceeded
            && exportResult.mixSucceeded
        let status: RecordingMetadata.Status = error == nil
            ? (allSucceeded ? .completed : .partial)
            : .failed
        let endedAt = Date.now
        let metadata = RecordingMetadata(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: Double(maxWrittenFrames) / 48_000,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            microphoneName: microphoneName,
            status: status,
            error: error ?? (allSucceeded ? nil : "One or more audio exports failed.")
        )
        if let data = try? JSONEncoder.metadataEncoder.encode(metadata) {
            try? data.write(to: files.metadataJSON, options: .atomic)
        }

        if error == nil {
            if allSucceeded {
                try? stateMachine.transition(to: .completed)
                publish(state: .completed)
            } else {
                try? stateMachine.transition(to: .failed(.init(message: "One or more audio exports failed.")))
                publish(state: stateMachine.state)
            }
        }
    }

    private func publish(state: RecordingState) {
        snapshot = RecordingSnapshot(
            state: state,
            elapsedSeconds: Double(maxWrittenFrames) / 48_000,
            systemLevel: snapshot.systemLevel,
            microphoneLevel: snapshot.microphoneLevel,
            outputDirectory: files?.directory
        )
        snapshotContinuation?.yield(snapshot)
    }

    private func publish(level: AudioLevel, for track: CaptureTrack) {
        snapshot = RecordingSnapshot(
            state: stateMachine.state,
            elapsedSeconds: Double(maxWrittenFrames) / 48_000,
            systemLevel: track == .system ? level : snapshot.systemLevel,
            microphoneLevel: track == .microphone ? level : snapshot.microphoneLevel,
            outputDirectory: files?.directory
        )
        snapshotContinuation?.yield(snapshot)
    }

    private func storeSnapshotContinuation(_ continuation: AsyncStream<RecordingSnapshot>.Continuation) {
        snapshotContinuation = continuation
    }

    private func currentCaptureTime() -> CMTime {
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        return max(hostTime, lastPresentationTime)
    }

    private static func defaultAvailableCapacity(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

private extension JSONEncoder {
    static var metadataEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
