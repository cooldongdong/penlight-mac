import AppKit
import Combine
import IOKit.hid
import ApplicationServices

/// The three macOS permissions Penlight needs, with live status.
enum Permission: String, CaseIterable, Identifiable {
    case inputMonitoring, screenRecording, accessibility
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: return "輸入監控"
        case .screenRecording: return "螢幕與系統錄音"
        case .accessibility: return "輔助使用"
        }
    }

    /// One line on why: what stops working without it.
    var reason: String {
        switch self {
        case .inputMonitoring: return "讀取簡報筆的按鍵。沒有它，Penlight 完全收不到簡報筆。"
        case .screenRecording: return "放大鏡要看得到螢幕；也用來辨認 Google 簡報。"
        case .accessibility: return "音量鍵的點擊與指揮中心、Google 簡報放映、指標速度。"
        }
    }

    var symbol: String {
        switch self {
        case .inputMonitoring: return "keyboard"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .accessibility: return "accessibility"
        }
    }

    var isGranted: Bool {
        switch self {
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted || CGPreflightListenEventAccess()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    /// Input Monitoring and Screen Recording only take effect after a relaunch.
    var needsRelaunch: Bool { self != .accessibility }

    /// Asks macOS (shows the system prompt the first time), then opens the right pane.
    func request() {
        switch self {
        case .inputMonitoring:
            // IOHIDRequestAccess alone did not add Penlight to the Input Monitoring list
            // (2026-11-07, macOS 26.6). Also try the CoreGraphics request; whether that
            // one registers the app on a fresh install is not verified yet.
            CGRequestListenEventAccess()
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .screenRecording: CGRequestScreenCaptureAccess()
        case .accessibility:
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        openSettings()
    }

    func openSettings() {
        let anchor: String
        switch self {
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
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
