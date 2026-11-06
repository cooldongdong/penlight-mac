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

// MARK: - Laser image chooser

enum LaserImageChooser {
    private static var panel: NSOpenPanel?

    /// Shown after the current SwiftUI update finishes (running a modal panel from
    /// inside onChange/a binding can fail silently), as a normal front window.
    static func choose(_ settings: EffectSettings, slot: EffectSettings.ImageSlot = .laser) {
        DispatchQueue.main.async {
            guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }
            let p = NSOpenPanel()
            p.allowedContentTypes = [.image]
            p.allowsMultipleSelection = false
            p.canChooseDirectories = false
            p.message = slot == .laser ? "選一張圖當雷射點（建議用去背的 PNG）" : "選一張圖給「圖片」模式"
            p.prompt = "使用這張圖"
            panel = p
            NSApp.activate(ignoringOtherApps: true)
            p.begin { response in
                if response == .OK, let url = p.url {
                    if !settings.setImage(slot, from: url) { penlightLog("laser image: could not read \(url.lastPathComponent)") }
                } else if slot == .laser, settings.laserImage == nil {
                    settings.useLaserImage = false
                }
                panel = nil
            }
            p.orderFrontRegardless()
            penlightLog("laser image chooser shown: visible=\(p.isVisible)")
        }
    }
}

// MARK: - Settings tabs

private struct GeneralTab: View {
    @ObservedObject var settings: EffectSettings

    private func chooseImage() { LaserImageChooser.choose(settings) }
    private func chooseStamp() { LaserImageChooser.choose(settings, slot: .stamp) }
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("雷射點") {
                Picker("樣式", selection: $settings.useLaserImage) {
                    Text("圓點").tag(false)
                    Text("自訂圖片").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.useLaserImage) { on in
                    if on && settings.laserImage == nil { chooseImage() }
                }
                HStack(alignment: .center) {
                    Text("圖片")
                    Spacer()
                    HStack(spacing: 10) {
                        // Fixed thumbnail slot: empty or filled, nothing moves.
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                            if let img = settings.laserImage {
                                Image(nsImage: img).resizable().scaledToFit().padding(3)
                            }
                        }
                        .frame(width: 32, height: 32)
                        Button("選擇圖片…", action: chooseImage)
                    }
                }
                .disabled(!settings.useLaserImage)
            }
            Section("圖片模式") {
                HStack(alignment: .center) {
                    Text("圖片")
                    Spacer()
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                            if let img = settings.stampImage {
                                Image(nsImage: img).resizable().scaledToFit().padding(3)
                            }
                        }
                        .frame(width: 32, height: 32)
                        Button("選擇圖片…", action: chooseStamp)
                    }
                }
            }
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
    var body: some View { DeviceKeysView(settings: settings) }
}

/// The pie drawn in the middle, each direction's picker placed on its side.
private struct PieTab: View {
    @ObservedObject var settings: EffectSettings

    var body: some View {
        VStack(spacing: 14) {
            Text("連按兩下模式鍵、第二下按住，往一個方向甩筆再放開。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ZStack {
                diagram
                editor(.pieUp).offset(y: -100)
                editor(.pieDown).offset(y: 124)
                editor(.pieLeft).offset(x: -172, y: 14)
                editor(.pieRight).offset(x: 172, y: 14)
            }
            .frame(width: 520, height: 290)
        }
        .padding(.top, 18)
    }

    /// Same look as the real pie, small.
    private var diagram: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.06))
            Path { p in
                p.move(to: CGPoint(x: 18, y: 18)); p.addLine(to: CGPoint(x: 102, y: 102))
                p.move(to: CGPoint(x: 102, y: 18)); p.addLine(to: CGPoint(x: 18, y: 102))
            }
            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            ForEach(PieMenu.slots, id: \.slot) { entry in
                Image(systemName: settings.action(for: entry.slot).symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(Self.iconOffset(entry.direction))
            }
            Circle().fill(Color.primary.opacity(0.5)).frame(width: 8, height: 8)
        }
        .frame(width: 120, height: 120)
    }

    private static func iconOffset(_ d: PieMenu.Direction) -> CGSize {
        switch d {
        case .up: return CGSize(width: 0, height: -38)
        case .down: return CGSize(width: 0, height: 38)
        case .left: return CGSize(width: -38, height: 0)
        case .right: return CGSize(width: 38, height: 0)
        }
    }

    private func editor(_ slot: KeySlot) -> some View {
        ActionPicker(settings: settings, slot: slot, showsLabel: false, compactWidth: 160)
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

/// Standard macOS settings window: toolbar tabs, one fixed size for every tab
/// (the window must not jump when switching tabs).
final class SettingsWindowController: NSWindowController {
    enum Tab: Int, CaseIterable { case general, keys, pie, permissions, about }

    private let tabs = SettingsTabs()
    private static let size = NSSize(width: 560, height: 480)

    init(settings: EffectSettings, state: AppState) {
        tabs.tabStyle = .toolbar
        func item<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.frame(width: Self.size.width, height: Self.size.height, alignment: .top))
            host.sizingOptions = []
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(item("一般", "gearshape", GeneralTab(settings: settings)))
        tabs.addTabViewItem(item("按鍵", "keyboard", KeysTab(settings: settings)))
        tabs.addTabViewItem(item("圓形選單", "circle.grid.cross", PieTab(settings: settings)))
        tabs.addTabViewItem(item("權限", "lock.shield", PermissionsTab(state: state)))
        tabs.addTabViewItem(item("關於", "info.circle", AboutTab()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.setContentSize(Self.size)
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
                    Text("開好這兩個權限就能開始。").font(.system(size: 13)).foregroundStyle(.secondary)
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
