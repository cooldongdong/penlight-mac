import AppKit
import Combine
import IOKit.hid
import ApplicationServices

/// The macOS permissions Penlight needs, with live status.
///
/// Input Monitoring is deliberately not on the list: Accessibility already lets an
/// app read keyboard and mouse input, and macOS then doesn't list it under Input
/// Monitoring at all (measured 2026-11-07: ListenEvent reset, Accessibility on →
/// both IOHIDCheckAccess and CGPreflightListenEventAccess report granted and the
/// pen works). Asking for one permission instead of two also avoids
/// IOHIDRequestAccess failing to add the app to the Input Monitoring list.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility, screenRecording
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "輔助使用"
        case .screenRecording: return "螢幕與系統錄音"
        }
    }

    /// One line on why: what stops working without it.
    var reason: String {
        switch self {
        case .accessibility: return "讀取簡報筆的按鍵，以及點擊、放映、指標速度。"
        case .screenRecording: return "放大鏡要看得到螢幕；也用來辨認 Google 簡報。"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// The pen's HID connection and screen capture are set up at launch, so both
    /// only take full effect after a relaunch.
    var needsRelaunch: Bool { true }

    /// Asks macOS (shows the system prompt the first time), then opens the right pane.
    func request() {
        switch self {
        case .accessibility:
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        case .screenRecording: CGRequestScreenCaptureAccess()
        }
        openSettings()
    }

    func openSettings() {
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

/// App-wide state shown in the panel, settings and onboarding.
final class AppState: ObservableObject {
    @Published var penConnected = false
    @Published private(set) var granted: [Permission: Bool] = [:]
    /// Permissions granted since launch that only work after a relaunch.
    @Published private(set) var pendingRelaunch = false

    private var launchGranted: [Permission: Bool] = [:]
    private var pollers = 0
    private var timer: Timer?

    init() {
        refresh()
        launchGranted = granted
        Self.logRawStatus()
    }

    /// Each underlying API on its own, to catch one of them lying.
    static func logRawStatus() {
        let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let hidText = hid == kIOHIDAccessTypeGranted ? "granted" : hid == kIOHIDAccessTypeDenied ? "denied" : "unknown"
        penlightLog("permissions: IOHIDCheckAccess=\(hidText) CGPreflightListenEvent=\(CGPreflightListenEventAccess()) "
            + "CGPreflightScreenCapture=\(CGPreflightScreenCaptureAccess()) AXTrusted=\(AXIsProcessTrusted())")
    }

    var allGranted: Bool { Permission.allCases.allSatisfy { granted[$0] == true } }

    func refresh() {
        var g: [Permission: Bool] = [:]
        for p in Permission.allCases { g[p] = p.isGranted }
        if g != granted { granted = g }
        let relaunch = Permission.allCases.contains { $0.needsRelaunch && g[$0] == true && launchGranted[$0] == false }
        if relaunch != pendingRelaunch { pendingRelaunch = relaunch }
    }

    /// Poll while some window shows permission status (System Settings has no callback).
    func beginPolling() {
        pollers += 1
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func endPolling() {
        pollers = max(pollers - 1, 0)
        if pollers == 0 { timer?.invalidate(); timer = nil }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
