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

/// Front view of the DR550DL, drawn from proportions measured on a photo of the
/// real device (our own drawing; no vendor artwork or logo).
///
/// Every position comes from one table of fractions of the body height, so keys,
/// side buttons and their labels can't drift out of line with each other.
struct PresenterDiagram: View {
    @Binding var selected: PenButton

    // Body: about 1 : 6.6 on the photo.
    private let bodyW: CGFloat = 54
    private let bodyH: CGFloat = 340
    private let top: CGFloat = 6

    /// Vertical centres, as a fraction of the body height (measured on the photo).
    private enum Y {
        static let led: CGFloat = 0.065
        static let mode: CGFloat = 0.21
        static let pageUp: CGFloat = 0.35
        static let pageDown: CGFloat = 0.48
        static let laser: CGFloat = 0.60
        static let volumeUp: CGFloat = 0.30   // right edge, between mode and page-up
        static let volumeDown: CGFloat = 0.43 // right edge, between page-up and page-down
        static let leftRidge: CGFloat = 0.17  // left edge, decorative
    }

    private var keyW: CGFloat { bodyW * 0.72 }
    private var keyH: CGFloat { keyW * 0.70 }
    private var sideLen: CGFloat { bodyH * 0.065 }

    private func y(_ f: CGFloat) -> CGFloat { top + bodyH * f }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let right = cx + bodyW / 2
            let left = cx - bodyW / 2
            ZStack {
                // Plug, behind the body
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.08))
                    .frame(width: bodyW * 0.36, height: 20)
                    .position(x: cx, y: top + bodyH + 6)
                // Body
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.19), Color(white: 0.23)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.09)))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: cx, y: top + bodyH / 2)
                // Status light
                Circle().fill(Color(white: 0.10)).frame(width: 4, height: 4)
                    .position(x: cx, y: y(Y.led))
                // Left ridge (not a button)
                Capsule().fill(Color(white: 0.30)).frame(width: 3, height: sideLen * 0.8)
                    .position(x: left - 1, y: y(Y.leftRidge))
                // Face keys
                faceKey(.mode, "smallcircle.filled.circle", at: CGPoint(x: cx, y: y(Y.mode)))
                faceKey(.pageUp, "chevron.up", at: CGPoint(x: cx, y: y(Y.pageUp)))
                faceKey(.pageDown, "chevron.down", at: CGPoint(x: cx, y: y(Y.pageDown)))
                faceKey(.laser, "sun.max", at: CGPoint(x: cx, y: y(Y.laser)), tint: .green)
                // Side keys, each label centred on its key
                sideKey(.volumeUp, "＋", edgeX: right, centerY: y(Y.volumeUp))
                sideKey(.volumeDown, "−", edgeX: right, centerY: y(Y.volumeDown))
            }
        }
        .frame(height: top + bodyH + 20)
    }

    private func faceKey(_ button: PenButton, _ symbol: String, at p: CGPoint, tint: Color = .white) -> some View {
        let on = selected == button
        return Button { selected = button } label: {
            RoundedRectangle(cornerRadius: keyH * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: keyH * 0.28, style: .continuous).stroke(Color.white.opacity(0.06)))
                .overlay(Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint.opacity(0.9)))
                .frame(width: keyW, height: keyH)
                .overlay(RoundedRectangle(cornerRadius: keyH * 0.28 + 3, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: on ? 2.5 : 0)
                    .frame(width: keyW + 6, height: keyH + 6))
                .frame(width: keyW + 10, height: keyH + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(button.title)
        .position(p)
    }

    /// The key sits on the body's edge; the label sits right of it on the same centre line.
    private func sideKey(_ button: PenButton, _ label: String, edgeX: CGFloat, centerY: CGFloat) -> some View {
        let on = selected == button
        let keyWidth: CGFloat = 4, labelWidth: CGFloat = 14, gap: CGFloat = 7
        return Button { selected = button } label: {
            HStack(alignment: .center, spacing: gap) {
                Capsule().fill(on ? Color.accentColor : Color(white: 0.36))
                    .frame(width: keyWidth, height: sideLen)
                Text(label).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                    .frame(width: labelWidth, height: sideLen)
            }
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(button.title)
        // HStack is centred on .position; shift so the capsule straddles the edge.
        .position(x: edgeX + (keyWidth + gap + labelWidth + 6) / 2 - 1, y: centerY)
    }
}
