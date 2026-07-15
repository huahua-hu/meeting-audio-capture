import AVFoundation
import CoreAudio
import Foundation

protocol DefaultInputDeviceMonitoring: Sendable {
    func currentDeviceID() -> String?
    func start(handler: @escaping @Sendable (String) -> Void) throws
    func stop()
}

protocol DefaultInputChangeSource: Sendable {
    func start(handler: @escaping @Sendable () -> Void) throws
    func stop()
}

final class SystemDefaultInputDeviceMonitor: DefaultInputDeviceMonitoring, @unchecked Sendable {
    private let source: any DefaultInputChangeSource
    private let deviceIDProvider: @Sendable () -> String?
    private let lock = NSLock()
    private var handler: (@Sendable (String) -> Void)?

    init(
        source: any DefaultInputChangeSource = CoreAudioDefaultInputChangeSource(),
        deviceIDProvider: @escaping @Sendable () -> String? = {
            AVCaptureDevice.default(for: .audio)?.uniqueID
        }
    ) {
        self.source = source
        self.deviceIDProvider = deviceIDProvider
    }

    func currentDeviceID() -> String? {
        deviceIDProvider()
    }

    func start(handler: @escaping @Sendable (String) -> Void) throws {
        lock.withLock { self.handler = handler }

        do {
            try source.start { [weak self] in
                self?.defaultInputDeviceDidChange()
            }
        } catch {
            lock.withLock { self.handler = nil }
            throw error
        }
    }

    func stop() {
        lock.withLock { handler = nil }
        source.stop()
    }

    private func defaultInputDeviceDidChange() {
        lock.withLock {
            guard let handler, let deviceID = deviceIDProvider() else { return }
            handler(deviceID)
        }
    }
}

final class CoreAudioDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var handler: (@Sendable () -> Void)?
    private var isListening = false
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.defaultInputDeviceDidChange()
    }

    func start(handler: @escaping @Sendable () -> Void) throws {
        let listener: AudioObjectPropertyListenerBlock? = lock.withLock {
            self.handler = handler
            guard !isListening else { return nil }
            isListening = true
            return self.listener
        }

        guard let listener else { return }

        var address = propertyAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            listener
        )

        guard status == noErr else {
            lock.withLock {
                self.handler = nil
                isListening = false
            }
            throw CaptureFailure.setupFailed(
                "Unable to monitor the default input device (CoreAudio status \(status))."
            )
        }
    }

    func stop() {
        let listener: AudioObjectPropertyListenerBlock? = lock.withLock {
            handler = nil
            guard isListening else { return nil }
            isListening = false
            return self.listener
        }

        guard let listener else { return }

        var address = propertyAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            listener
        )
    }

    private func defaultInputDeviceDidChange() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}
