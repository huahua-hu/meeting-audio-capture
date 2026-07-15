import AVFoundation
import CoreAudio
import Dispatch
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
    private let lifecycleLock = NSRecursiveLock()
    private let stateLock = NSLock()
    private let callbackQueue = DispatchQueue(label: "MeetingAudioCapture.default-input-monitor")
    private let callbackQueueKey = DispatchSpecificKey<Void>()
    private var generation: UInt64 = 0
    private var isActive = false
    private var handler: (@Sendable (String) -> Void)?

    init(
        source: any DefaultInputChangeSource = CoreAudioDefaultInputChangeSource(),
        deviceIDProvider: @escaping @Sendable () -> String? = {
            AVCaptureDevice.default(for: .audio)?.uniqueID
        }
    ) {
        self.source = source
        self.deviceIDProvider = deviceIDProvider
        callbackQueue.setSpecific(key: callbackQueueKey, value: ())
    }

    func currentDeviceID() -> String? {
        deviceIDProvider()
    }

    func start(handler: @escaping @Sendable (String) -> Void) throws {
        lifecycleLock.lock()
        let generation = stateLock.withLock {
            self.generation &+= 1
            isActive = false
            self.handler = handler
            return self.generation
        }

        do {
            try source.start { [weak self] in
                self?.enqueueDefaultInputDeviceChange(for: generation)
            }
        } catch {
            stateLock.withLock {
                guard self.generation == generation else { return }
                self.generation &+= 1
                isActive = false
                self.handler = nil
            }
            source.stop()
            lifecycleLock.unlock()
            drainCallbackQueue()
            throw error
        }

        stateLock.withLock {
            guard self.generation == generation else { return }
            isActive = true
        }
        lifecycleLock.unlock()
    }

    func stop() {
        lifecycleLock.lock()
        stateLock.withLock {
            generation &+= 1
            isActive = false
            handler = nil
        }
        source.stop()
        lifecycleLock.unlock()
        drainCallbackQueue()
    }

    private func enqueueDefaultInputDeviceChange(for generation: UInt64) {
        callbackQueue.async { [weak self] in
            self?.deliverDefaultInputDeviceChange(for: generation)
        }
    }

    private func deliverDefaultInputDeviceChange(for generation: UInt64) {
        let shouldResolveDevice = stateLock.withLock {
            isActive && self.generation == generation && self.handler != nil
        }
        guard shouldResolveDevice, let deviceID = deviceIDProvider() else { return }

        let handler: (@Sendable (String) -> Void)? = stateLock.withLock {
            guard isActive, self.generation == generation else { return nil }
            return self.handler
        }
        handler?(deviceID)
    }

    private func drainCallbackQueue() {
        guard DispatchQueue.getSpecific(key: callbackQueueKey) == nil else { return }
        callbackQueue.sync {}
    }
}

final class CoreAudioDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    typealias AddListener = (@escaping AudioObjectPropertyListenerBlock) -> OSStatus
    typealias RemoveListener = (@escaping AudioObjectPropertyListenerBlock) -> Void

    private let transitionLock = NSLock()
    private let stateLock = NSLock()
    private let addListener: AddListener
    private let removeListener: RemoveListener
    private var handler: (@Sendable () -> Void)?
    private var isListening = false
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.defaultInputDeviceDidChange()
    }

    init(
        addListener: @escaping AddListener = { listener in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            return AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                nil,
                listener
            )
        },
        removeListener: @escaping RemoveListener = { listener in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                nil,
                listener
            )
        }
    ) {
        self.addListener = addListener
        self.removeListener = removeListener
    }

    deinit {
        stop()
    }

    func start(handler: @escaping @Sendable () -> Void) throws {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        let listener: AudioObjectPropertyListenerBlock? = stateLock.withLock {
            self.handler = handler
            guard !isListening else { return nil }
            return self.listener
        }

        guard let listener else { return }

        let status = addListener(listener)

        guard status == noErr else {
            stateLock.withLock {
                self.handler = nil
                isListening = false
            }
            throw CaptureFailure.setupFailed(
                "Unable to monitor the default input device (CoreAudio status \(status))."
            )
        }

        stateLock.withLock { isListening = true }
    }

    func stop() {
        transitionLock.lock()
        defer { transitionLock.unlock() }

        let listener: AudioObjectPropertyListenerBlock? = stateLock.withLock {
            handler = nil
            guard isListening else { return nil }
            isListening = false
            return self.listener
        }

        guard let listener else { return }

        removeListener(listener)
    }

    private func defaultInputDeviceDidChange() {
        let handler = stateLock.withLock {
            isListening ? self.handler : nil
        }
        handler?()
    }
}
