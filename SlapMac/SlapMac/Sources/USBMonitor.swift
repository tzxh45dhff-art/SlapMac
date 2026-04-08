// USBMonitor.swift
// SlapMac – USB Plug/Unplug Detection
//
// Uses Apple's IOKit framework to watch for USB devices being
// connected or disconnected, then fires the onUSBEvent callback.
//
// Note: App Sandbox must be DISABLED for this to work (see SETUP.md).
import Foundation
import IOKit
import IOKit.usb

// A module-level reference so the C-style callbacks can reach our class.
// (C callbacks can't capture Swift objects directly, so this is the workaround.)
nonisolated(unsafe) private weak var _usbMonitorInstance: USBMonitor?

// Opt out of MainActor isolation — IOKit callbacks arrive on arbitrary threads.
nonisolated(unsafe) class USBMonitor {

private var notificationPort: IONotificationPortRef?
private var connectedIterator: io_iterator_t = 0
private var disconnectedIterator: io_iterator_t = 0

/// Called with `true` when a USB device is plugged in, `false` when removed.
var onUSBEvent: @Sendable (Bool) -> Void

init(onUSBEvent: @escaping @Sendable (Bool) -> Void) {
    self.onUSBEvent = onUSBEvent
}

func start() {
    _usbMonitorInstance = self

    // Create a notification port and add it to the run loop
    notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    guard let port = notificationPort else {
        print("⚠️ USBMonitor: Failed to create IONotificationPort")
        return
    }

    let runLoopSource = IONotificationPortGetRunLoopSource(port).takeRetainedValue()
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

    // --- Watch for USB devices connecting ---
    let connectDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
    IOServiceAddMatchingNotification(
        port,
        kIOFirstMatchNotification,
        connectDict,
        usbConnectedCallback,  // called when a new USB device appears
        nil,
        &connectedIterator
    )
    // Drain the iterator on startup — these are already-connected devices,
    // we don't want to play a sound for them.
    drainIterator(connectedIterator, fireCallback: false)

    // --- Watch for USB devices disconnecting ---
    let disconnectDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
    IOServiceAddMatchingNotification(
        port,
        kIOTerminatedNotification,
        disconnectDict,
        usbDisconnectedCallback,  // called when a USB device is removed
        nil,
        &disconnectedIterator
    )
    drainIterator(disconnectedIterator, fireCallback: false)
}

/// Empties an IOKit iterator. If `fireCallback` is true, triggers the event handler.
private func drainIterator(_ iterator: io_iterator_t, fireCallback: Bool) {
    var service = IOIteratorNext(iterator)
    while service != 0 {
        IOObjectRelease(service)
        if fireCallback { onUSBEvent(true) }
        service = IOIteratorNext(iterator)
    }
}

}

// MARK: - C-style Callbacks
// These are plain functions (not methods) because IOKit requires C-compatible callbacks.

nonisolated private func usbConnectedCallback(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
var service = IOIteratorNext(iterator)
while service != 0 {
IOObjectRelease(service)
_usbMonitorInstance?.onUSBEvent(true)
service = IOIteratorNext(iterator)
}
}

nonisolated private func usbDisconnectedCallback(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
var service = IOIteratorNext(iterator)
while service != 0 {
IOObjectRelease(service)
_usbMonitorInstance?.onUSBEvent(false)
service = IOIteratorNext(iterator)
}
}
