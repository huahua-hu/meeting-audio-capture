@testable import MeetingAudioCapture
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

        XCTAssertEqual(monitor.currentDeviceID(), "built-in")
        try monitor.start { received.append($0) }
        source.emit()

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

        try monitor.start { received.append($0) }
        monitor.stop()
        source.emit()

        XCTAssertEqual(received.values(), [])
    }
}

private final class TestDefaultInputChangeSource: DefaultInputChangeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func start(handler: @escaping @Sendable () -> Void) throws {
        lock.withLock { self.handler = handler }
    }

    func stop() {
        lock.withLock { handler = nil }
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
