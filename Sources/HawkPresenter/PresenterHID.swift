import Foundation
import IOKit.hid

/// Talks to the "Wireless Present" USB dongle (VID 0x2571, PID 0x4109).
///
/// Protocol, decoded by sniffing (see README):
/// - Vendor input report 4, byte[1]. Values below 0x10 are a bit field:
///     0x04  mode key held (the pen also starts moving the cursor via its gyro)
///     0x01  page-up held while mode key held (stays set until released;
///           the dongle swallows the real Page Up)
///     0x02  page-down held while mode key held
///     0x08  mode key double-tapped
///   Values from 0x10 up are whole codes, not flags:
///     0xED  volume-up pressed while mode key held (system volume unaffected)
///     0xEE  volume-down pressed while mode key held
///     0x80  heartbeat, roughly once a second — ignore
/// - Page up/down, long-press page up/down, volume keys arrive as ordinary
///   keyboard/consumer reports; macOS handles them without us.
final class PresenterHID {
    enum Event {
        case holdBegan
        case holdEnded
        /// Page up/down went down while holding; `adjustEnded` follows on release.
        case adjustBegan(bigger: Bool)
        case adjustEnded
        case volumeUpWhileHeld
        case volumeDownWhileHeld
        case doubleTap
        /// Double-tap whose second press is held (0x08, then 0x04 ~0.5 s later).
        /// Ends with `gestureEnded` instead of `holdEnded`.
        case gestureBegan
        case gestureEnded
        case connected(Bool)
    }

    static let vendorID = 0x2571
    static let productID = 0x4109

    var onEvent: ((Event) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var lastBits: UInt8 = 0
    private var lastRaw: UInt8 = 0
    private var held = false
    private var lastPenMouse = Date.distantPast
    private var releaseTimer: Timer?
    /// Set between a 0x08 and either a following hold (→ gesture) or the timeout (→ doubleTap).
    private var pendingDoubleTap: DispatchWorkItem?
    private var inGesture = false
    /// After 0x08 the dongle sends 0x04 about 0.5 s later if the second press is held.
    private let doubleTapHoldWindow: TimeInterval = 0.8

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
        defer { lastRaw = raw }

        if raw >= 0x10 {
            // Whole codes; all of them imply the mode key is held.
            markHeld()
            if raw != lastRaw && !inGesture {
                if raw == 0xED { onEvent?(.volumeUpWhileHeld) }
                if raw == 0xEE { onEvent?(.volumeDownWhileHeld) }
            }
            return
        }

        let bits = raw
        defer { lastBits = bits }
        if bits & 0x08 != 0 && lastBits & 0x08 == 0 && !held {
            pendingDoubleTap?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingDoubleTap = nil
                self?.onEvent?(.doubleTap)
            }
            pendingDoubleTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapHoldWindow, execute: work)
        }

        let adjust = bits & 0x03, lastAdjust = lastBits & 0x03
        if adjust != lastAdjust && !inGesture {
            if lastAdjust != 0 { onEvent?(.adjustEnded) }
            if adjust == 0x01 { onEvent?(.adjustBegan(bigger: true)) }
            if adjust == 0x02 { onEvent?(.adjustBegan(bigger: false)) }
        }

        if bits & 0x04 != 0 {
            markHeld()
        } else if held {
            scheduleReleaseCheck()
        }
    }

    private func markHeld() {
        releaseTimer?.invalidate(); releaseTimer = nil
        guard !held else { return }
        held = true
        if let pending = pendingDoubleTap {
            pending.cancel(); pendingDoubleTap = nil
            inGesture = true
            onEvent?(.gestureBegan)
        } else {
            onEvent?(.holdBegan)
        }
    }

    private func scheduleReleaseCheck() {
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.lastBits & 0x04 != 0 || self.lastRaw >= 0x10 { t.invalidate(); return }
            if Date().timeIntervalSince(self.lastPenMouse) >= self.releaseQuietInterval {
                t.invalidate()
                self.held = false
                if self.inGesture {
                    self.inGesture = false
                    self.onEvent?(.gestureEnded)
                } else {
                    self.onEvent?(.holdEnded)
                }
            }
        }
    }
}
