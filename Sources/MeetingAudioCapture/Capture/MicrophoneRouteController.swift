import Foundation

actor MicrophoneRouteController {
    typealias ApplyDevice = @Sendable (String) async throws -> Void
    typealias RetryDelay = @Sendable () async -> Void

    private let followsSystemDefault: Bool
    private let retryDelay: RetryDelay
    private let applyDevice: ApplyDevice
    private var activeDeviceID: String?
    private var desiredDeviceID: String?
    private var isStopped = false
    private var routeWorkerTask: Task<Void, Never>?
    private var retryDelayTask: Task<Void, Never>?

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
              let deviceID else { return }

        if deviceID == activeDeviceID, desiredDeviceID == nil {
            return
        }

        desiredDeviceID = deviceID
        retryDelayTask?.cancel()

        let worker: Task<Void, Never>
        if let routeWorkerTask {
            worker = routeWorkerTask
        } else {
            worker = Task { await runRouteWorker() }
            routeWorkerTask = worker
        }

        await worker.value
    }

    func stop() async {
        isStopped = true
        desiredDeviceID = nil
        retryDelayTask?.cancel()
        await routeWorkerTask?.value
    }

    private func runRouteWorker() async {
        while !isStopped, let deviceID = desiredDeviceID {
            if deviceID == activeDeviceID {
                desiredDeviceID = nil
                break
            }

            do {
                try await applyDevice(deviceID)
                activeDeviceID = deviceID

                if desiredDeviceID == deviceID {
                    desiredDeviceID = nil
                }
            } catch {
                guard !isStopped else { break }

                let delay = Task { [retryDelay] in
                    await retryDelay()
                }
                retryDelayTask = delay
                await delay.value
                retryDelayTask = nil
            }
        }

        routeWorkerTask = nil
        retryDelayTask = nil
    }
}
