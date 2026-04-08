// SlapDetector.swift
// SlapMac – Accelerometer-based Slap Detection
//
// Reads the undocumented MEMS accelerometer on Apple Silicon MacBooks
// via IOKit HID (AppleSPUHIDDevice, Bosch BMI286 IMU).
//
// The sensor is on vendor usage page 0xFF00, usage 3.
// Reports are 22 bytes: X/Y/Z as int32 little-endian at byte offsets 6, 10, 14.
// Divide raw values by 65536.0 to get acceleration in g.

import Foundation
import IOKit
import IOKit.hid

nonisolated(unsafe) final class SlapDetector {

    // MARK: - Constants

    private static let kVendorUsagePage: Int = 0xFF00
    private static let kAccelUsage: Int = 3
    private static let kReportLength: Int = 22
    private static let kDataOffset: Int = 6
    private static let kAccelScale: Double = 65536.0
    private static let kReportBufSize: Int = 4096
    private static let kReportIntervalUS: Int32 = 1000

    // MARK: - Properties

    private let onSlap: @Sendable (Double) -> Void

    /// Impact threshold in g-force.
    /// Lower = more sensitive (lighter taps trigger).
    /// Higher = less sensitive (needs harder hits).
    /// Default 0.6g works well on both soft and hard surfaces.
    var threshold: Double = 0.6

    /// Cooldown in seconds between slap detections.
    var cooldown: Double = 0.4

    private var hidDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var isCoolingDown = false

    // Gravity baseline (exponential moving average)
    private var gravityX: Double = 0.0
    private var gravityY: Double = 0.0
    private var gravityZ: Double = -1.0
    private let gravityAlpha: Double = 0.02  // Very slow, so impacts don't shift it
    private var hasBaseline = false
    private var baselineCount: Int = 0
    private let baselineSettleCount: Int = 50

    // Peak detector: holds the max magnitude over a sliding window
    // so short hard-surface spikes (1-3 samples) are reliably caught
    private var peakMagnitude: Double = 0.0
    private var peakAge: Int = 0
    private let peakWindowSize: Int = 6  // ~7ms at 800Hz

    // MARK: - Init

    init(onSlap: @escaping @Sendable (Double) -> Void) {
        self.onSlap = onSlap
    }

    deinit {
        stop()
    }

    // MARK: - Public

    static func isAvailable() -> Bool {
        let matching = IOServiceMatching("AppleSPUHIDDevice") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return false }

        var found = false
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let usagePage = registryPropertyInt(service, key: "PrimaryUsagePage"),
               let usage = registryPropertyInt(service, key: "PrimaryUsage"),
               usagePage == kVendorUsagePage && usage == kAccelUsage {
                found = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return found
    }

    func start() {
        guard hidDevice == nil else { return }

        wakeSPUDrivers()

        guard let device = findAccelerometerDevice() else {
            print("⚠️ SlapDetector: No Apple Silicon accelerometer found.")
            return
        }

        hidDevice = device

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            print("⚠️ SlapDetector: Failed to open HID device (error \(openResult)).")
            hidDevice = nil
            return
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.kReportBufSize)
        buffer.initialize(repeating: 0, count: Self.kReportBufSize)
        reportBuffer = buffer

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            CFIndex(Self.kReportBufSize),
            hidReportCallback,
            context
        )

        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        print("✅ SlapDetector: Accelerometer connected, listening for slaps...")
    }

    func stop() {
        if let device = hidDevice {
            IOHIDDeviceUnscheduleFromRunLoop(
                device,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidDevice = nil

        if let buffer = reportBuffer {
            buffer.deallocate()
            reportBuffer = nil
        }

        print("🛑 SlapDetector: Stopped.")
    }

    // MARK: - IOKit Helpers

    private func wakeSPUDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            setRegistryProperty(service, key: "SensorPropertyReportingState", value: 1)
            setRegistryProperty(service, key: "SensorPropertyPowerState", value: 1)
            setRegistryProperty(service, key: "ReportInterval", value: Self.kReportIntervalUS)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }

    private func findAccelerometerDevice() -> IOHIDDevice? {
        let matching = IOServiceMatching("AppleSPUHIDDevice") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }

        var foundDevice: IOHIDDevice?
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let usagePage = Self.registryPropertyInt(service, key: "PrimaryUsagePage"),
               let usage = Self.registryPropertyInt(service, key: "PrimaryUsage"),
               usagePage == Self.kVendorUsagePage && usage == Self.kAccelUsage {
                foundDevice = IOHIDDeviceCreate(kCFAllocatorDefault, service)
                IOObjectRelease(service)
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return foundDevice
    }

    private static func registryPropertyInt(_ entry: io_service_t, key: String) -> Int? {
        guard let cfProp = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }

        if let number = cfProp as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func setRegistryProperty(_ entry: io_service_t, key: String, value: Int32) {
        let number = NSNumber(value: value)
        IORegistryEntrySetCFProperty(entry, key as CFString, number)
    }

    // MARK: - HID Report Processing

    /// Process every raw 22-byte report at ~800Hz.
    /// No decimation — we process every sample so short hard-surface
    /// spikes (1-3 samples at ~1.2ms each) are never missed.
    fileprivate func processReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length == Self.kReportLength else { return }

        // Parse X/Y/Z (memcpy to avoid alignment traps at offset 6)
        var rawX: Int32 = 0
        var rawY: Int32 = 0
        var rawZ: Int32 = 0
        memcpy(&rawX, report.advanced(by: Self.kDataOffset),     4)
        memcpy(&rawY, report.advanced(by: Self.kDataOffset + 4), 4)
        memcpy(&rawZ, report.advanced(by: Self.kDataOffset + 8), 4)

        let ax = Double(rawX) / Self.kAccelScale
        let ay = Double(rawY) / Self.kAccelScale
        let az = Double(rawZ) / Self.kAccelScale

        // ── Initial baseline: average the first N samples ──
        if !hasBaseline {
            baselineCount += 1
            if baselineCount == 1 {
                gravityX = ax; gravityY = ay; gravityZ = az
            } else {
                let n = Double(baselineCount)
                gravityX += (ax - gravityX) / n
                gravityY += (ay - gravityY) / n
                gravityZ += (az - gravityZ) / n
            }
            if baselineCount >= baselineSettleCount {
                hasBaseline = true
            }
            return
        }

        // ── Dynamic acceleration (gravity removed) ──
        let dx = ax - gravityX
        let dy = ay - gravityY
        let dz = az - gravityZ
        let magnitude = sqrt(dx * dx + dy * dy + dz * dz)

        // ── Update gravity only when idle ──
        // Freeze gravity updates during impacts so baseline stays clean
        if magnitude < threshold * 0.4 {
            gravityX = gravityAlpha * ax + (1.0 - gravityAlpha) * gravityX
            gravityY = gravityAlpha * ay + (1.0 - gravityAlpha) * gravityY
            gravityZ = gravityAlpha * az + (1.0 - gravityAlpha) * gravityZ
        }

        // ── Peak-hold detector ──
        // On hard surfaces, impact spikes last only 1-3 samples.
        // We hold the peak for `peakWindowSize` samples, then evaluate.
        if magnitude > peakMagnitude {
            peakMagnitude = magnitude
            peakAge = 0
        } else {
            peakAge += 1
        }

        // Window expired — evaluate the captured peak
        guard peakAge >= peakWindowSize, peakMagnitude > 0 else { return }

        let peak = peakMagnitude
        peakMagnitude = 0
        peakAge = 0

        guard peak > threshold, !isCoolingDown else { return }

        let intensity = min((peak - threshold) / 3.0, 1.0)

        let capturedIntensity = intensity
        let capturedOnSlap = onSlap
        DispatchQueue.main.async {
            capturedOnSlap(capturedIntensity)
        }

        isCoolingDown = true
        let cd = cooldown
        DispatchQueue.main.asyncAfter(deadline: .now() + cd) { [weak self] in
            self?.isCoolingDown = false
        }
    }
}

// MARK: - C-style HID Callback

nonisolated func hidReportCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ type: IOHIDReportType,
    _ reportID: UInt32,
    _ report: UnsafeMutablePointer<UInt8>,
    _ reportLength: CFIndex
) {
    guard let context = context else { return }
    let detector = Unmanaged<SlapDetector>.fromOpaque(context).takeUnretainedValue()
    detector.processReport(report, length: Int(reportLength))
}
