import SwiftUI

/// The panel that drops down from the menu-bar icon: what you touch during a talk.
/// Everything else lives in the Settings window.
struct PanelView: View {
    @ObservedObject var settings: EffectSettings
    @ObservedObject var state: AppState
    var onOpenSettings: () -> Void
    var onOpenPermissions: () -> Void

    static let width: CGFloat = 300
    /// Same height for every mode, so switching modes never resizes the panel.
    private let modeSectionHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modeTiles
            Divider()
            modeControls.frame(height: modeSectionHeight, alignment: .top)
            Divider()
            row("指標速度") { slider($settings.pointerSpeed, 0.3...3) }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: Self.width)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.penConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(state.penConnected ? "簡報筆已連線" : "簡報筆未連線")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !state.allGranted {
                Button(action: onOpenPermissions) {
                    Label("權限未完成", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
            }
        }
    }

    private var modeTiles: some View {
        HStack(spacing: 8) {
            ForEach(EffectMode.allCases, id: \.self) { mode in
                let on = settings.mode == mode
                Button { settings.mode = mode } label: {
                    VStack(spacing: 5) {
                        Image(systemName: mode.symbol).font(.system(size: 17, weight: .medium))
                        Text(mode.title).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(on ? Color.accentColor : Color.primary.opacity(0.07))
                    )
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One quick control for the current mode; everything else is in Settings → 外觀.
    @ViewBuilder private var modeControls: some View {
        switch settings.mode {
        case .laser: row("大小") { slider($settings.laserRadius, 6...60) }
        case .spotlight: row("範圍") { slider($settings.spotlightRadius, 60...600) }
        case .magnifier: row("倍率") { slider($settings.zoom, 1.5...5) }
        case .pointer: row("光暈") { slider($settings.pointerHaloRadius, 16...90) }
        case .image: row("大小") { slider($settings.imageModeSize, 60...900) }
        }
    }

    private var footer: some View {
        HStack {
            Button("設定…", action: onOpenSettings).keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("結束 Penlight") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
    }

    // MARK: Helpers

    /// Label column has a fixed width so every control starts and ends at the same x.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 24)
    }

    private func slider(_ value: Binding<CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }), in: range)
        .controlSize(.small)
    }
}
