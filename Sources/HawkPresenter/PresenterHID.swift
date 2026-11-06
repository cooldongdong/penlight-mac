import Foundation
import IOKit.hid

/// Talks to the "Wireless Present" USB dongle (VID 0x2571, PID 0x4109).
///
/// Protocol, decoded by sniffing (see README):
/// - Vendor input report 4, byte[1] is a bit field:
///     0x04  mode key held (the pen also starts moving the cursor via its gyro)
///     0x01  page-up pressed while mode key held (dongle swallows the real Page Up)
///     0x02  page-down pressed while mode key held
///     0x08  mode key double-tapped
///     0x80  heartbeat, roughly once a second — ignore
/// - Page up/down, long-press page up/down, volume keys arrive as ordinary
///   keyboard/consumer reports; macOS handles them without us.
final class PresenterHID {
    enum Event {
        case holdBegan
        case holdEnded
        case pageUpWhileHeld
        case pageDownWhileHeld
        case doubleTap
        case connected(Bool)
    }

    static let vendorID = 0x2571
    static let productID = 0x4109

    var onEvent: ((Event) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var lastBits: UInt8 = 0
    private var held = false
    private var lastPenMouse = Date.distantPast
    private var releaseTimer: Timer?

    /// The pen sometimes reports 0x00 while the key is still physically held
    /// (cursor keeps moving). Only treat it as released once the pen's mouse
    /// reports have also gone quiet for this long.
    private let releaseQuietInterval: TimeInterval = 0.15

    func start() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().onEvent?(.connected(false))
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            NSLog("HawkPresenter: IOHIDManagerOpen failed 0x%08x (Input Monitoring permission?)", r)
        }
    }

    private func attach(_ device: IOHIDDevice) {
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let size = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 1)
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffers.append(buf)
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        if page == 0x01 && usage == 0x02 {
            // Pen's gyro mouse: we only use it to know whether the pen is still moving.
            IOHIDDeviceRegisterInputReportCallback(device, buf, size, { ctx, _, _, _, _, _, _ in
                Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().lastPenMouse = Date()
            }, ctx)
        } else if page == 0x01 && usage == 0x06 {
            IOHIDDeviceRegisterInputReportCallback(device, buf, size, { ctx, _, _, _, reportID, report, length in
                guard reportID == 4, length >= 2 else { return }
                Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().handle(bits: report[1])
            }, ctx)
            onEvent?(.connected(true))
        }
    }

    private func handle(bits raw: UInt8) {
        if raw == 0x80 { return } // heartbeat
        let bits = raw & 0x0F
        defer { lastBits = bits }

        if bits & 0x08 != 0 && lastBits & 0x08 == 0 { onEvent?(.doubleTap) }

        if bits & 0x04 != 0 {
            releaseTimer?.invalidate(); releaseTimer = nil
            if !held { held = true; onEvent?(.holdBegan) }
            if bits & 0x01 != 0 && lastBits & 0x01 == 0 { onEvent?(.pageUpWhileHeld) }
            if bits & 0x02 != 0 && lastBits & 0x02 == 0 { onEvent?(.pageDownWhileHeld) }
        } else if held {
            scheduleReleaseCheck()
        }
    }

    private func scheduleReleaseCheck() {
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.lastBits & 0x04 != 0 { t.invalidate(); return }
            if Date().timeIntervalSince(self.lastPenMouse) >= self.releaseQuietInterval {
                t.invalidate()
                self.held = false
                self.onEvent?(.holdEnded)
            }
        }
    }
}
