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
                        .frame(width: 84, alignment: .leading)
                    // 84 + 10 + 168 + 8 + 58 + padding 36 = 364 ≤ 369 available: the diagram is never squeezed.
                    ActionPicker(settings: settings, slot: slot, showsLabel: false, inline: (picker: 168, recorder: 58))
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

/// Front view of the DR550DL, drawn from measurements of a photo of the real
/// device (our own drawing; no vendor artwork or logo).
///
/// Measured on a 168×625 px photo: body 116×540 px (1 : 4.66). Every size and
/// position below is a fraction of the body's width (W) or height (H), so keys,
/// side buttons and labels can't drift out of line with each other.
struct PresenterDiagram: View {
    @Binding var selected: PenButton

    private let bodyH: CGFloat = 310
    private var bodyW: CGFloat { bodyH / 4.66 }
    private let top: CGFloat = 4

    private struct Key {
        let button: PenButton
        let symbol: String
        let centerY: CGFloat      // fraction of H
        let size: CGSize          // fractions of W (width) and H (height)
        var tint: Color = .white
    }

    // Page keys are larger (59×47 px) than mode / laser (47×34 px).
    private let keys: [Key] = [
        Key(button: .mode, symbol: "smallcircle.filled.circle", centerY: 0.147, size: CGSize(width: 0.405, height: 0.063)),
        Key(button: .pageUp, symbol: "chevron.up", centerY: 0.259, size: CGSize(width: 0.509, height: 0.087)),
        Key(button: .pageDown, symbol: "chevron.down", centerY: 0.381, size: CGSize(width: 0.509, height: 0.087)),
        Key(button: .laser, symbol: "sun.max", centerY: 0.494, size: CGSize(width: 0.405, height: 0.063), tint: .green),
    ]
    private let ledY: CGFloat = 0.057
    private let volumeUpY: CGFloat = 0.209, volumeDownY: CGFloat = 0.322, sideLen: CGFloat = 0.076
    private let ridgeY: CGFloat = 0.159, ridgeLen: CGFloat = 0.113

    private func y(_ f: CGFloat) -> CGFloat { top + bodyH * f }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let right = cx + bodyW / 2
            let left = cx - bodyW / 2
            ZStack {
                // Plug (0.405 W wide), tucked behind the body
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.07))
                    .frame(width: bodyW * 0.405, height: bodyH * 0.10)
                    .position(x: cx, y: top + bodyH + bodyH * 0.04)
                // Body
                RoundedRectangle(cornerRadius: bodyW * 0.11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.33), Color(white: 0.29), Color(white: 0.19)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: bodyW * 0.11, style: .continuous).stroke(Color.white.opacity(0.08)))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: cx, y: top + bodyH / 2)
                Circle().fill(Color(white: 0.08)).frame(width: 4, height: 4)
                    .position(x: cx, y: y(ledY))
                // Left ridge (not a button)
                Capsule().fill(Color(white: 0.26)).frame(width: 3, height: bodyH * ridgeLen)
                    .position(x: left - 0.5, y: y(ridgeY))
                ForEach(keys, id: \.button) { key in faceKey(key, cx: cx) }
                sideKey(.volumeUp, "＋", edgeX: right, centerY: y(volumeUpY))
                sideKey(.volumeDown, "−", edgeX: right, centerY: y(volumeDownY))
            }
        }
        .frame(height: top + bodyH + bodyH * 0.10)
    }

    private func faceKey(_ key: Key, cx: CGFloat) -> some View {
        let on = selected == key.button
        let w = bodyW * key.size.width, h = bodyH * key.size.height, r = h * 0.24
        return Button { selected = key.button } label: {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.white.opacity(0.07)))
                .overlay(Image(systemName: key.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(key.tint.opacity(0.9)))
                .frame(width: w, height: h)
                .overlay(RoundedRectangle(cornerRadius: r + 3, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: on ? 2.5 : 0)
                    .frame(width: w + 6, height: h + 6))
                .frame(width: w + 10, height: h + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key.button.title)
        .position(x: cx, y: y(key.centerY))
    }

    /// The key straddles the body's right edge; its label sits on the same centre line.
    private func sideKey(_ button: PenButton, _ label: String, edgeX: CGFloat, centerY: CGFloat) -> some View {
        let on = selected == button
        let keyWidth: CGFloat = 4, labelWidth: CGFloat = 14, gap: CGFloat = 7
        let len = bodyH * sideLen
        return Button { selected = button } label: {
            HStack(alignment: .center, spacing: gap) {
                Capsule().fill(on ? Color.accentColor : Color(white: 0.30))
                    .frame(width: keyWidth, height: len)
                Text(label).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(width: labelWidth, height: len)
            }
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(button.title)
        .position(x: edgeX + (keyWidth + gap + labelWidth + 6) / 2 - 1.5, y: centerY)
    }
}
