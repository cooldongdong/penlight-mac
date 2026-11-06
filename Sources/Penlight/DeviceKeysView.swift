import SwiftUI

/// Settings → 按鍵: a drawing of the presenter on the left (our own drawing, not the
/// vendor's artwork); click a button to edit what it does on the right.
struct DeviceKeysView: View {
    @ObservedObject var settings: EffectSettings
    @State private var selected: PenButton = Self.initialButton

    /// `--keys <n>` preselects a button, for screenshots.
    private static var initialButton: PenButton {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--keys"), i + 1 < args.count, let n = Int(args[i + 1]),
           PenButton.allCases.indices.contains(n) { return PenButton.allCases[n] }
        return .pageUp
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            PresenterDiagram(selected: $selected)
                .frame(width: 190)
                .layoutPriority(1) // never squeezed by the detail column
                .padding(.top, 14)
            Divider()
            detail
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selected.title).font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 14)
            ForEach(selected.slots, id: \.self) { slot in
                HStack(spacing: 10) {
                    Text(slot.title).font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    ActionPicker(settings: settings, slot: slot, showsLabel: false, inline: (picker: 150, recorder: 64))
                }
                .frame(height: 34)
            }
            if let note = selected.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, selected.slots.isEmpty ? 0 : 10)
            }
        }
    }
}

/// Front view of the DR550DL: four keys down the face, volume keys on the right edge.
struct PresenterDiagram: View {
    @Binding var selected: PenButton

    private let bodySize = CGSize(width: 70, height: 296)

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let top: CGFloat = 8
            ZStack {
                // Body
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.20)], startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10)))
                    .frame(width: bodySize.width, height: bodySize.height)
                    .position(x: cx, y: top + bodySize.height / 2)
                // Status light
                Circle().fill(Color(white: 0.12)).frame(width: 5, height: 5)
                    .position(x: cx, y: top + 14)
                // Face keys
                faceKey(.mode, "smallcircle.filled.circle", y: top + 42)
                faceKey(.pageUp, "chevron.up", y: top + 82)
                faceKey(.pageDown, "chevron.down", y: top + 122)
                faceKey(.laser, "sun.max", y: top + 162, tint: .green)
                // Side keys on the right edge, labelled outside the body
                sideKey(.volumeUp, label: "＋", x: cx + bodySize.width / 2 + 1, y: top + 72)
                sideKey(.volumeDown, label: "−", x: cx + bodySize.width / 2 + 1, y: top + 112)
                // USB plug
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.15))
                    .frame(width: 18, height: 10)
                    .position(x: cx, y: top + bodySize.height + 4)
            }
        }
        .frame(height: bodySize.height + 24)
    }

    private func faceKey(_ button: PenButton, _ symbol: String, y: CGFloat, tint: Color = .white) -> some View {
        let on = selected == button
        return GeometryReader { geo in
            Button { selected = button } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: 0.10))
                    .frame(width: 34, height: 28)
                    .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint.opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: on ? 2.5 : 0)
                        .frame(width: 40, height: 34))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(button.title)
            .position(x: geo.size.width / 2, y: y)
        }
    }

    private func sideKey(_ button: PenButton, label: String, x: CGFloat, y: CGFloat) -> some View {
        let on = selected == button
        return Button { selected = button } label: {
            HStack(spacing: 6) {
                Capsule().fill(on ? Color.accentColor : Color(white: 0.38)).frame(width: 5, height: 26)
                Text(label).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .padding(.vertical, 4).padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(button.title)
        .position(x: x + 12, y: y)
    }
}
