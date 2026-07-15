@testable import MeetingAudioCapture
import CoreAudio
import Dispatch
import Foundation
import XCTest

final class DefaultInputDeviceMonitorTests: XCTestCase {
    func testEmitsResolvedDeviceWhenHardwareSourceChanges() throws {
        let source = TestDefaultInputChangeSource()
        let ids = LockedValues(["built-in", "headset"])
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: { ids.removeFirst() }
        )
        let received = LockedValues<String>([])
        let delivered = expectation(description: "device change delivered")

        XCTAssertEqual(monitor.currentDeviceID(), "built-in")
        try monitor.start {
            received.append($0)
            delivered.fulfill()
        }
        source.emit()
        wait(for: [delivered], timeout: 0.5)

        XCTAssertEqual(received.values(), ["headset"])
        monitor.stop()
        source.emit()
        XCTAssertEqual(received.values(), ["headset"])
    }

    func testStopPreventsDeliveryFromRetainedSourceCallback() throws {
        let source = RetainingDefaultInputChangeSource()
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: { "headset" }
        )
        let received = LockedValues<String>([])
        let delivered = expectation(description: "consumer handler called")
        delivered.isInverted = true

        try monitor.start {
            received.append($0)
            delivered.fulfill()
        }
        monitor.stop()
        source.emit()

        wait(for: [delivered], timeout: 0.1)
        XCTAssertEqual(received.values(), [])
    }

    func testHandlerCanSynchronouslyStopMonitor() throws {
        let source = TestDefaultInputChangeSource()
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: { "headset" }
        )
        let stopReturned = expectation(description: "handler stop returned")

        try monitor.start { _ in
            monitor.stop()
            stopReturned.fulfill()
        }

        DispatchQueue.global().async {
            source.emit()
        }

        wait(for: [stopReturned], timeout: 0.5)
    }

    func testDeviceIDProviderCanSynchronouslyStopMonitor() throws {
        let source = TestDefaultInputChangeSource()
        let monitorReference = LockedReference<SystemDefaultInputDeviceMonitor>()
        let stopReturned = expectation(description: "provider stop returned")
        let delivered = expectation(description: "consumer handler called")
        delivered.isInverted = true
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: {
                monitorReference.value()?.stop()
                stopReturned.fulfill()
                return "headset"
            }
        )
        monitorReference.set(monitor)
        try monitor.start { _ in delivered.fulfill() }

        DispatchQueue.global().async {
            source.emit()
        }

        wait(for: [stopReturned, delivered], timeout: 0.5)
    }

    func testStopWaitsForInFlightProviderAndSuppressesConsumer() throws {
        let providerEntered = DispatchSemaphore(value: 0)
        let allowProviderToFinish = DispatchSemaphore(value: 0)
        let sourceStopped = DispatchSemaphore(value: 0)
        let stopReturned = DispatchSemaphore(value: 0)
        let source = TestDefaultInputChangeSource {
            sourceStopped.signal()
        }
        let delivered = expectation(description: "consumer handler called")
        delivered.isInverted = true
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: {
                providerEntered.signal()
                allowProviderToFinish.wait()
                return "headset"
            }
        )
        try monitor.start { _ in delivered.fulfill() }

        source.emit()
        XCTAssertEqual(providerEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            monitor.stop()
            stopReturned.signal()
        }
        XCTAssertEqual(sourceStopped.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(stopReturned.wait(timeout: .now() + 0.1), .timedOut)

        allowProviderToFinish.signal()
        XCTAssertEqual(stopReturned.wait(timeout: .now() + 1), .success)
        wait(for: [delivered], timeout: 0.1)
    }

    func testFailedStartStopsPartiallyStartedSourceAndSuppressesItsCallback() {
        let source = PartiallyStartingDefaultInputChangeSource()
        let monitor = SystemDefaultInputDeviceMonitor(
            source: source,
            deviceIDProvider: { "headset" }
        )
        let delivered = expectation(description: "consumer handler called")
        delivered.isInverted = true

        XCTAssertThrowsError(
            try monitor.start { _ in delivered.fulfill() }
        )
        XCTAssertEqual(source.stopCallCount(), 1)

        source.emit()
        wait(for: [delivered], timeout: 0.1)
    }

    func testCoreAudioSourceSerializesConcurrentStartAndStopUsingSameListener() {
        let addEntered = DispatchSemaphore(value: 0)
        let allowAddToFinish = DispatchSemaphore(value: 0)
        let stopStarted = DispatchSemaphore(value: 0)
        let removeCalled = DispatchSemaphore(value: 0)
        let listenerIdentities = LockedListenerIdentities()
        let startError = LockedReference<any Error>()
        let source = CoreAudioDefaultInputChangeSource(
            addListener: { listener in
                listenerIdentities.recordAdded(listener)
                addEntered.signal()
                allowAddToFinish.wait()
                return noErr
            },
            removeListener: { listener in
                listenerIdentities.recordRemoved(listener)
                removeCalled.signal()
            }
        )
        let startFinished = expectation(description: "start finished")
        let stopFinished = expectation(description: "stop finished")

        DispatchQueue.global().async {
            do {
                try source.start {}
            } catch {
                startError.set(error)
            }
            startFinished.fulfill()
        }

        XCTAssertEqual(addEntered.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async {
            stopStarted.signal()
            source.stop()
            stopFinished.fulfill()
        }
        XCTAssertEqual(stopStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(removeCalled.wait(timeout: .now() + 0.1), .timedOut)

        allowAddToFinish.signal()
        wait(for: [startFinished, stopFinished], timeout: 1)

        XCTAssertNil(startError.value())
        XCTAssertEqual(removeCalled.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(listenerIdentities.match())
    }

    func testCoreAudioSourceRemovesSameListenerOnDeinit() throws {
        let removeCalled = DispatchSemaphore(value: 0)
        let listenerIdentities = LockedListenerIdentities()
        var source: CoreAudioDefaultInputChangeSource? = CoreAudioDefaultInputChangeSource(
            addListener: { listener in
                listenerIdentities.recordAdded(listener)
                return noErr
            },
            removeListener: { listener in
                listenerIdentities.recordRemoved(listener)
                removeCalled.signal()
            }
        )
        weak var weakSource = source

        try source?.start {}
        source = nil

        XCTAssertNil(weakSource)
        XCTAssertEqual(removeCalled.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(listenerIdentities.match())
    }
}

private final class TestDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let onStop: @Sendable () -> Void
    private var handler: (@Sendable () -> Void)?

    init(onStop: @escaping @Sendable () -> Void = {}) {
        self.onStop = onStop
    }

    func start(handler: @escaping @Sendable () -> Void) throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock { handler = nil }
        onStop()
    }

    func emit() {
        let callback = lock.withLock { handler }
        callback?()
    }
}

private final class RetainingDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func start(handler: @escaping @Sendable () -> Void) throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {}

    func emit() {
        let callback = lock.withLock { handler }
        callback?()
    }
}

private enum TestStartFailure: Error {
    case partiallyStarted
}

private final class PartiallyStartingDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var stops = 0

    func start(handler: @escaping @Sendable () -> Void) throws {
        lock.withLock { self.handler = handler }
        throw TestStartFailure.partiallyStarted
    }

    func stop() {
        lock.withLock { stops += 1 }
    }

    func emit() {
        let callback = lock.withLock { handler }
        callback?()
    }

    func stopCallCount() -> Int {
        lock.withLock { stops }
    }
}

private final class LockedReference<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }

    func value() -> Value? {
        lock.withLock { storage }
    }
}

private final class LockedListenerIdentities: @unchecked Sendable {
    private let lock = NSLock()
    private var added: AudioObjectPropertyListenerBlock?
    private var removed: AudioObjectPropertyListenerBlock?

    func recordAdded(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        lock.withLock { added = listener }
    }

    func recordRemoved(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        lock.withLock { removed = listener }
    }

    func match() -> Bool {
        lock.withLock {
            guard let added, let removed else { return false }
            return ObjectIdentifier(added as AnyObject) == ObjectIdentifier(removed as AnyObject)
        }
    }
}

private final class LockedValues<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element]

    init(_ values: [Element]) { storage = values }

    func append(_ value: Element) {
        lock.withLock { storage.append(value) }
    }

    func removeFirst() -> Element? {
        lock.withLock { storage.isEmpty ? nil : storage.removeFirst() }
    }

    func values() -> [Element] {
        lock.withLock { storage }
    }
}
