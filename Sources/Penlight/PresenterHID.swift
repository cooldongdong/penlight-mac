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
        /// Consumer-page key from report 2 (0xE9 volume up, 0xEA volume down); 0 = released.
        case consumer(UInt16)
    }

    static let vendorID = 0x2571
    static let productID = 0x4109

    var onEvent: ((Event) -> Void)?
    /// When the pen did something on its keyboard interface (any report 1/2), for
    /// telling its keys apart from the Mac keyboard's. Arrives 1–13 ms before the
    /// system delivers the same key to event taps (measured 2026-11-07).
    private(set) var lastKeyReportAt: CFAbsoluteTime = 0
    /// Called with the pen's raw gyro motion while the mouse interface is seized.
    var onMouseDelta: ((Int, Int) -> Void)?
    private var mouseDevice: IOHIDDevice?
    private(set) var mouseSeized = false
    private var wantMouseSeized = false

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
            kIOHIDPrimaryUsagePageKey: 0x01,
            kIOHIDPrimaryUsageKey: 0x06,
        ] as CFDictionary)
        startMouseThread()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().onEvent?(.connected(false))
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess {
            NSLog("Penlight: IOHIDManagerOpen failed 0x%08x (Input Monitoring permission?)", r)
        }
    }

    private func attach(_ device: IOHIDDevice) {
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let size = max(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64, 1)
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffers.append(buf)
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        if page == 0x01 && usage == 0x06 {
            IOHIDDeviceRegisterInputReportCallback(device, buf, size, { ctx, _, _, _, reportID, report, length in
                let me = Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue()
                switch reportID {
                case 4 where length >= 2:
                    me.handle(bits: report[1])
                case 1:
                    me.lastKeyReportAt = CFAbsoluteTimeGetCurrent()
                case 2 where length >= 3:
                    me.lastKeyReportAt = CFAbsoluteTimeGetCurrent()
                    me.onEvent?(.consumer(UInt16(report[1]) | UInt16(report[2]) << 8))
                default: break
                }
            }, ctx)
            onEvent?(.connected(true))
        }
    }

    /// Take the pen's mouse away from the system (it stops moving the cursor by itself).
    /// Allowed for mouse-class devices without root; released automatically on quit.
    func seizeMouse(_ on: Bool) {
        onMouseThread { self.applySeize(on) }
    }

    private func applySeize(_ on: Bool) {
        wantMouseSeized = on
        guard let d = mouseDevice, on != mouseSeized else { return }
        if on {
            let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            mouseSeized = r == kIOReturnSuccess
            penlightLog("seize pen mouse: \(String(format: "0x%08x", r))")
        } else {
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            mouseSeized = false
        }
    }

    // MARK: Gyro mouse on its own thread
    //
    // The pen's motion is handled off the main thread so drawing the overlay
    // (spotlight, magnifier) never delays the cursor.

    private var mouseRunLoop: CFRunLoop?
    private let mouseManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var mouseBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    private func startMouseThread() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.mouseRunLoop = CFRunLoopGetCurrent()
            IOHIDManagerSetDeviceMatching(self.mouseManager, [
                kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID,
                kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: 0x02,
            ] as CFDictionary)
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(self.mouseManager, { ctx, _, _, device in
                Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue().attachMouse(device)
            }, ctx)
            IOHIDManagerRegisterDeviceRemovalCallback(self.mouseManager, { ctx, _, _, _ in
                let me = Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue()
                me.mouseDevice = nil; me.mouseSeized = false
            }, ctx)
            IOHIDManagerScheduleWithRunLoop(self.mouseManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(self.mouseManager, IOOptionBits(kIOHIDOptionsTypeNone))
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "penlight.mouse"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    private func onMouseThread(_ block: @escaping () -> Void) {
        guard let rl = mouseRunLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    /// Report: buttons, dx (int8), dy (int8), wheel. Always used to know whether the
    /// pen is still moving; when seized we also move the cursor ourselves (pointer speed).
    private func attachMouse(_ device: IOHIDDevice) {
        mouseDevice = device
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, mouseBuffer, 64, { ctx, _, _, _, _, report, length in
            let me = Unmanaged<PresenterHID>.fromOpaque(ctx!).takeUnretainedValue()
            me.lastPenMouse = Date()
            if me.mouseSeized, length >= 3 {
                me.onMouseDelta?(Int(Int8(bitPattern: report[1])), Int(Int8(bitPattern: report[2])))
            }
        }, ctx)
        if wantMouseSeized { applySeize(true) } // re-plugged dongle
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
