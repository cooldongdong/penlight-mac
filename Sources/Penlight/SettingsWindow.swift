import AppKit
import SwiftUI

// MARK: - Shared: permission rows

/// One row per permission: what it is, why, and either ✓ or a button.
struct PermissionsList: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Permission.allCases) { p in
                HStack(spacing: 12) {
                    Image(systemName: p.symbol)
                        .font(.system(size: 18))
                        .frame(width: 28)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.system(size: 13, weight: .semibold))
                        Text(p.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    // Fixed-width trailing slot: ✓ and the button occupy the same space.
                    Group {
                        if state.granted[p] == true {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.green)
                        } else {
                            Button("允許") { p.request() }.controlSize(.small)
                        }
                    }
                    .frame(width: 56, alignment: .trailing)
                }
                .padding(.vertical, 10)
                if p != Permission.allCases.last { Divider() }
            }
            if state.pendingRelaunch {
                HStack {
                    Text("剛開的權限要重新開啟 Penlight 才會生效。").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("重新開啟") { AppState.relaunch() }.controlSize(.small)
                }
                .padding(.top, 10)
            }
        }
        .onAppear { state.beginPolling() }
        .onDisappear { state.endPolling() }
    }
}

// MARK: - Settings tabs

private struct GeneralTab: View {
    @ObservedObject var settings: EffectSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("顯示") {
                Toggle("切換模式時顯示模式名稱", isOn: $settings.showModeHUD)
            }
            Section("啟動") {
                Toggle("登入時自動開啟 Penlight", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        loginError = LoginItem.set(on)
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                } else if LoginItem.needsApproval {
                    Text("請到「系統設定 → 一般 → 登入項目」允許 Penlight。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeysTab: View {
    @ObservedObject var settings: EffectSettings

    var body: some View {
        Form {
            Section {
                ForEach(KeySlot.allCases, id: \.self) { slot in
                    Picker(slot.title, selection: Binding(
                        get: { settings.action(for: slot) },
                        set: { settings.setAction($0, for: slot) }
                    )) {
                        ForEach(PenAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("音量鍵")
            } footer: {
                Text("按住模式鍵時，音量鍵固定用來切換模式。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsTab: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section { PermissionsList(state: state) }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "laser.burst").font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text("Penlight").font(.system(size: 20, weight: .semibold))
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("給 Hawk DR550DL 簡報筆用的非官方工具，與原廠無關。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Link("github.com/cooldongdong/penlight-mac", destination: URL(string: "https://github.com/cooldongdong/penlight-mac")!)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

// MARK: - Window

/// Toolbar tabs that, like System Settings panes, title the window after the
/// selected tab and resize the window to that tab's content.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        // The window mirrors its content view controller's title.
        title = item?.label ?? "Penlight"
    }
}

/// Standard macOS settings window: toolbar tabs, fixed width, height follows the tab.
final class SettingsWindowController: NSWindowController {
    enum Tab: Int, CaseIterable { case general, keys, permissions, about }

    private let tabs = SettingsTabs()
    private static let width: CGFloat = 520

    init(settings: EffectSettings, state: AppState) {
        tabs.tabStyle = .toolbar
        func item<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.frame(width: Self.width).fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(item("一般", "gearshape", GeneralTab(settings: settings)))
        tabs.addTabViewItem(item("按鍵", "keyboard", KeysTab(settings: settings)))
        tabs.addTabViewItem(item("權限", "lock.shield", PermissionsTab(state: state)))
        tabs.addTabViewItem(item("關於", "info.circle", AboutTab()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = tabs.tabViewItems.first?.label ?? "Penlight"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ tab: Tab? = nil) {
        if let tab { tabs.selectedTabViewItemIndex = tab.rawValue }
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Onboarding

private struct OnboardingView: View {
    @ObservedObject var state: AppState
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "laser.burst").font(.system(size: 34)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("歡迎使用 Penlight").font(.system(size: 20, weight: .semibold))
                    Text("開好這三個權限就能開始。").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            PermissionsList(state: state)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            HStack {
                if !state.allGranted && !state.pendingRelaunch {
                    Button("稍後再說", action: onDone)
                }
                Spacer()
                if state.pendingRelaunch {
                    Button("重新開啟 Penlight") { AppState.relaunch() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("開始使用", action: onDone).keyboardShortcut(.defaultAction).disabled(!state.allGranted)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

final class OnboardingWindowController: NSWindowController {
    init(state: AppState) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Penlight"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(state: state) { [weak self] in
            self?.close()
        })
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
