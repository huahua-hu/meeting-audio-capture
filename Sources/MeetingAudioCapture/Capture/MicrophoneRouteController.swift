import Foundation

actor MicrophoneRouteController {
    typealias ApplyDevice = @Sendable (String) async throws -> Void
    typealias RetryDelay = @Sendable () async -> Void

    private let followsSystemDefault: Bool
    private let retryDelay: RetryDelay
    private let applyDevice: ApplyDevice
    private var activeDeviceID: String?
    private var targetDeviceID: String?
    private var generation = 0
    private var isStopped = false
    private var retryTask: Task<Void, Never>?

    init(
        requestedDeviceID: String?,
        initialDefaultDeviceID: String?,
        retryDelay: @escaping RetryDelay = {
            try? await Task.sleep(nanoseconds: 500_000_000)
        },
        applyDevice: @escaping ApplyDevice
    ) {
        followsSystemDefault = requestedDeviceID == nil
        activeDeviceID = requestedDeviceID ?? initialDefaultDeviceID
        self.retryDelay = retryDelay
        self.applyDevice = applyDevice
    }

    func defaultDeviceDidChange(to deviceID: String?) async {
        guard followsSystemDefault,
              !isStopped,
              let deviceID,
              deviceID != targetDeviceID else { return }

        if deviceID == activeDeviceID {
            guard targetDeviceID != nil else { return }
            cancelPendingWork()
            return
        }

        cancelPendingWork()
        targetDeviceID = deviceID
        let updateGeneration = generation

        let worker = Task { [weak self, applyDevice, retryDelay] in
            while !Task.isCancelled {
                do {
                    try await applyDevice(deviceID)
                } catch {
                    guard !Task.isCancelled else { return }
                    await retryDelay()
                    continue
                }

                guard !Task.isCancelled else { return }
                await self?.didApply(deviceID, generation: updateGeneration)
                return
            }
        }
        retryTask = worker
        await worker.value
    }

    func stop() {
        isStopped = true
        cancelPendingWork()
    }

    private func cancelPendingWork() {
        generation += 1
        targetDeviceID = nil
        retryTask?.cancel()
        retryTask = nil
    }

    private func didApply(_ deviceID: String, generation: Int) {
        guard !isStopped,
              generation == self.generation,
              targetDeviceID == deviceID else { return }

        activeDeviceID = deviceID
        targetDeviceID = nil
        retryTask = nil
    }
}
