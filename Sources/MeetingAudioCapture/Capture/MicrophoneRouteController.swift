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
              deviceID != activeDeviceID,
              deviceID != targetDeviceID else { return }

        targetDeviceID = deviceID
        generation += 1
        let updateGeneration = generation

        while !isStopped, generation == updateGeneration {
            do {
                try await applyDevice(deviceID)
                guard !isStopped, generation == updateGeneration else { return }
                activeDeviceID = deviceID
                targetDeviceID = nil
                return
            } catch {
                await retryDelay()
            }
        }
    }

    func stop() {
        isStopped = true
        generation += 1
        targetDeviceID = nil
    }
}
