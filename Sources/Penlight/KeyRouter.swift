import AppKit

/// Intercepts key events that came from the pen and reroutes them.
///
/// macOS won't let a normal app seize a keyboard-class device, so the pen's keys
/// still reach the system. We tell them apart from the Mac keyboard by:
/// - key events: keyboard type 40 (the Mac's built-in keyboard reports 106), and
/// - media keys (no keyboard type): the pen's raw HID report arrives 1–13 ms
///   before the system event, so "pen reported a key within the last 60 ms".
///
/// Needs Accessibility (an active, modifying event tap).
final class KeyRouter {
    /// Asked on every pen volume key: should the system still get it?
    var passVolumeToSystem: (_ up: Bool) -> Bool = { _ in true }
    var lastPenKeyReport: () -> CFAbsoluteTime = { 0 }
    var googleSlidesEnabled = true
    /// Fired once the tap is installed, i.e. Accessibility has been granted.
    var onInstalled: (() -> Void)?

    private var tap: CFMachPort?
    private var retry: Timer?
    private let penKeyboardType: Int64 = 40
    private let penWindow: CFAbsoluteTime = 0.06
    /// Long-press page-up sends Shift+F5 then ⌘⌥P ~50 ms later; swallow the pair.
    private var swallowCmdOptPUntil: CFAbsoluteTime = 0
    private var swallowedKeyUps = Set<Int64>()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        if !Self.isTrusted {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        installWhenTrusted()
    }

    private func installWhenTrusted() {
        if install() { return }
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            if self?.install() == true { t.invalidate() }
        }
    }

    private func install() -> Bool {
        guard tap == nil, Self.isTrusted else { return tap != nil }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << 14)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, ctx in
            let router = Unmanaged<KeyRouter>.fromOpaque(ctx!).takeUnretainedValue()
            return router.handle(type: type, event: event)
        }, userInfo: me) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        penlightLog("key router installed")
        onInstalled?()
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag { return pass }

        if type.rawValue == 14 { return handleMediaKey(event) }

        guard event.getIntegerValueField(.keyboardEventKeyboardType) == penKeyboardType else { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp, swallowedKeyUps.remove(code) != nil { return nil }
        guard type == .keyDown else { return pass }

        // Long-press page-up = "start slideshow": Shift+F5 (PowerPoint) then ⌘⌥P (Keynote).
        if code == 96, event.flags.contains(.maskShift), googleSlidesEnabled, Self.frontIsGoogleSlides() {
            swallowedKeyUps.insert(96)
            swallowCmdOptPUntil = CFAbsoluteTimeGetCurrent() + 0.3
            ActionRunner.press(keyCode: 36, flags: .maskCommand) // ⌘Return = Present
            return nil
        }
        if code == 35, CFAbsoluteTimeGetCurrent() < swallowCmdOptPUntil {
            swallowedKeyUps.insert(35)
            return nil
        }
        return pass
    }

    private func handleMediaKey(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        guard key == 0 || key == 1 else { return pass } // sound up / down only
        guard CFAbsoluteTimeGetCurrent() - lastPenKeyReport() < penWindow else { return pass } // Mac keyboard
        return passVolumeToSystem(key == 0) ? pass : nil
    }

    /// True when the front window is a Google Slides deck (URL first, title as fallback).
    static func frontIsGoogleSlides() -> Bool {
        // The page URL is the reliable signal; some browsers (Dia) truncate window titles.
        if let url = FrontDocument.url() { return url.contains("docs.google.com/presentation/") }
        let title = FrontDocument.title() ?? frontWindowTitle()
        return ["Google 簡報", "Google Slides", "Google 幻灯片"].contains { title.contains($0) }
    }

    static func frontWindowTitle() -> String {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return "" }
        return list.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowName as String] as? String ?? ""
    }
}
