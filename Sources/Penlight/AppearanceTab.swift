import AppKit
import SwiftUI

/// Settings → 外觀: set up how each mode looks, before the talk.
/// A mock slide on top shows the effect live under the mouse, at screen scale.
struct AppearanceTab: View {
    @ObservedObject var settings: EffectSettings
    @State private var editing: EffectMode = .laser
    @AppStorage("previewDarkSlide") private var darkSlide = false

    /// Fixed so switching modes never moves anything below.
    private let controlsHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 14) {
            PreviewStage(settings: settings, mode: editing, dark: darkSlide)
                .frame(height: 196)
                .overlay(alignment: .topTrailing) {
                    // One toggle button: a segmented control squeezed into an overlay rendered half-drawn.
                    Button { darkSlide.toggle() } label: {
                        Image(systemName: darkSlide ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(darkSlide ? Color.white : Color.black.opacity(0.7))
                            .frame(width: 28, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(darkSlide ? Color.white.opacity(0.14) : Color.black.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .help(darkSlide ? "改成淺色投影片" : "改成深色投影片")
                }
            Picker("", selection: $editing) {
                ForEach(EffectMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            controls
                .frame(height: controlsHeight, alignment: .top)
        }
        .padding(20)
        .onAppear { editing = settings.mode }
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch editing {
            case .laser:
                row("樣式") { laserStyle }
                row("顏色") { ColorPalette(settings: settings) }
                row("自訂") { HueStrip(settings: settings) }
                row("大小") { slider($settings.laserRadius, 6...60) }
            case .spotlight:
                row("範圍") { slider($settings.spotlightRadius, 60...600) }
                row("背景") { slider($settings.spotlightDim, 0.2...0.95) }
            case .magnifier:
                row("倍率") { slider($settings.zoom, 1.5...5) }
                row("鏡片") { slider($settings.lensRadius, 100...320) }
            case .pointer:
                row("顏色") { ColorPalette(settings: settings) }
                row("自訂") { HueStrip(settings: settings) }
                row("光暈") { slider($settings.pointerHaloRadius, 16...90) }
            case .image:
                row("圖片") { imagePicker(settings.stampImage, enabled: true) { LaserImageChooser.choose(settings, slot: .stamp) } }
                row("大小") { slider($settings.imageModeSize, 60...900) }
            }
        }
    }

    private var laserStyle: some View {
        HStack(spacing: 14) {
            Picker("", selection: $settings.useLaserImage) {
                Text("圓點").tag(false)
                Text("圖片").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
            .onChange(of: settings.useLaserImage) { on in
                if on && settings.laserImage == nil { LaserImageChooser.choose(settings) }
            }
            // Always present (dimmed for the dot) so nothing shifts when switching.
            imagePicker(settings.laserImage, enabled: settings.useLaserImage) { LaserImageChooser.choose(settings) }
            Spacer(minLength: 0)
        }
    }

    private func imagePicker(_ image: NSImage?, enabled: Bool, choose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07))
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(2) }
            }
            .frame(width: 26, height: 26)
            Button("選擇圖片…", action: choose).controlSize(.small)
        }
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 26)
    }

    private func slider(_ value: Binding<CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }), in: range)
            .controlSize(.small)
    }
}

// MARK: - Colour

/// Seven rainbow presets plus the current custom colour.
struct ColorPalette: View {
    @ObservedObject var settings: EffectSettings

    var body: some View {
        HStack(spacing: 10) {
            ForEach(EffectSettings.laserPresets, id: \.0) { name, color in
                swatch(Color(nsColor: color), selected: settings.laserColor.hexRGB == color.hexRGB) {
                    settings.laserColor = color
                }
                .help(name)
            }
            // Custom: rainbow ring around the colour last picked on the strip below.
            let custom = Color(nsColor: HueStrip.color(hue: HueStrip.storedHue))
            Button { settings.laserColor = HueStrip.color(hue: HueStrip.storedHue) } label: {
                ZStack {
                    Circle().strokeBorder(AngularGradient(colors: HueStrip.rainbow, center: .center), lineWidth: 3)
                    Circle().fill(custom).padding(5)
                }
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.primary.opacity(settings.isPresetColor ? 0 : 0.85), lineWidth: 2).frame(width: 28, height: 28))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("自訂顏色")
        }
    }

    private func swatch(_ color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2).frame(width: 26, height: 26))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A hue bar: drag anywhere on it to pick a custom colour, right here (no colour window).
struct HueStrip: View {
    @ObservedObject var settings: EffectSettings
    @AppStorage("customHue") private var hue: Double = 0.83

    static let rainbow: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 0.85, brightness: 1) }
    static var storedHue: Double { UserDefaults.standard.object(forKey: "customHue") as? Double ?? 0.83 }
    static func color(hue: Double) -> NSColor { NSColor(hue: hue, saturation: 0.85, brightness: 1, alpha: 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: Self.rainbow, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                Circle()
                    .fill(Color(nsColor: Self.color(hue: hue)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 18, height: 18)
                    .offset(x: hue * (w - 18))
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                hue = min(max(Double((g.location.x - 9) / max(w - 18, 1)), 0), 1)
                settings.laserColor = Self.color(hue: hue)
            })
        }
        .frame(height: 22)
        .padding(.trailing, 4)
    }
}

// MARK: - Stage

/// A mock slide with the effect drawn at the mouse (or a resting spot), at the same
/// scale as a real screen of the Mac's main display.
struct PreviewStage: View {
    @ObservedObject var settings: EffectSettings
    let mode: EffectMode
    let dark: Bool
    @State private var hover: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Resting spot: over the chart, so every effect has something to act on.
            let p = hover ?? CGPoint(x: size.width * 0.84, y: size.height * 0.62)
            let k = size.width / (NSScreen.main?.frame.width ?? 1440)
            ZStack {
                MockSlide(dark: dark)
                effect(at: p, scale: k, size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12)))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hover = loc
                case .ended: hover = nil
                }
            }
        }
    }

    @ViewBuilder private func effect(at p: CGPoint, scale k: CGFloat, size: CGSize) -> some View {
        let color = Color(nsColor: settings.laserColor)
        switch mode {
        case .laser:
            if settings.useLaserImage, let img = settings.laserImage {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(width: settings.laserRadius * 3 * k, height: settings.laserRadius * 3 * k).position(p)
            } else {
                let r = settings.laserRadius * k
                ZStack {
                    Circle().fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)], center: .center,
                                                 startRadius: r * 0.6, endRadius: r * 2.2))
                        .frame(width: r * 4.4, height: r * 4.4)
                    Circle().fill(color).frame(width: r * 2, height: r * 2)
                    Circle().fill(Color.white.opacity(0.85)).frame(width: r * 0.7, height: r * 0.7)
                }
                .position(p)
            }
        case .spotlight:
            let r = settings.spotlightRadius * k
            Canvas { ctx, s in
                var path = Path(CGRect(origin: .zero, size: s))
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(path, with: .color(.black.opacity(settings.spotlightDim)), style: FillStyle(eoFill: true))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(0.25)), lineWidth: 1.5)
            }
        case .magnifier:
            let r = settings.lensRadius * k
            ZStack {
                MockSlide(dark: dark)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(settings.zoom, anchor: UnitPoint(x: p.x / size.width, y: p.y / size.height))
                    .mask(Circle().frame(width: r * 2, height: r * 2).position(p))
                // Two-tone rim: visible on light and dark slides alike.
                Circle().stroke(Color.black.opacity(0.35), lineWidth: 3.5).frame(width: r * 2, height: r * 2).position(p)
                Circle().stroke(Color.white.opacity(0.95), lineWidth: 1.5).frame(width: r * 2, height: r * 2).position(p)
            }
        case .pointer:
            let r = settings.pointerHaloRadius * k
            ZStack {
                Circle().fill(color.opacity(0.18)).overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1.5))
                    .frame(width: r * 2, height: r * 2).position(p)
                Image(systemName: "cursorarrow").font(.system(size: 13)).foregroundStyle(dark ? .white : .black)
                    .position(x: p.x + 4, y: p.y + 7)
            }
        case .image:
            let box = settings.imageModeSize * k
            if let img = settings.stampImage {
                Image(nsImage: img).resizable().scaledToFit().frame(width: box, height: box).position(p)
            } else {
                RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(dark ? Color.white.opacity(0.7) : Color.black.opacity(0.4))
                    .frame(width: box, height: box).position(p)
            }
        }
    }
}

/// A believable keynote-style slide: eyebrow, headline, one line of support,
/// three figures, and a quarterly chart with the latest quarter highlighted.
private struct MockSlide: View {
    let dark: Bool

    private var fg: Color { dark ? Color(white: 0.96) : Color(red: 0.08, green: 0.08, blue: 0.10) }
    private var sub: Color { dark ? Color(white: 0.62) : Color(white: 0.42) }
    private var faint: Color { dark ? Color.white.opacity(0.13) : Color.black.opacity(0.09) }
    private let accent = Color(red: 0.37, green: 0.36, blue: 0.95) // indigo: reads on light and dark

    private let quarters: [(String, CGFloat)] = [("Q4", 0.46), ("Q1", 0.58), ("Q2", 0.66), ("Q3", 0.92)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                background
                // Left column
                VStack(alignment: .leading, spacing: 0) {
                    Text("Q3 REVIEW")
                        .font(.system(size: 8.5, weight: .semibold)).tracking(1.8)
                        .foregroundStyle(accent)
                    Text("Growth that\ncompounds.")
                        .font(.system(size: 23, weight: .bold)).tracking(-0.6)
                        .lineSpacing(-3)
                        .foregroundStyle(fg)
                        .padding(.top, 7)
                    Text("Revenue up 18% while retention hit a record high.")
                        .font(.system(size: 9.5)).foregroundStyle(sub)
                        .lineLimit(2).frame(width: w * 0.36, alignment: .leading)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: 18) {
                        figure("+18%", "Revenue")
                        figure("42", "New clients")
                        figure("91%", "Retention")
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 22)
                .frame(width: w * 0.52, height: h, alignment: .topLeading)

                // Right column: chart
                chart(height: h * 0.52)
                    .frame(width: w * 0.34, height: h * 0.52 + 30, alignment: .bottom)
                    .position(x: w * 0.77, y: h * 0.56)

                Text("12").font(.system(size: 8, weight: .medium)).foregroundStyle(sub.opacity(0.7))
                    .position(x: w - 18, y: h - 14)
            }
        }
    }

    private var background: some View {
        ZStack {
            if dark {
                LinearGradient(colors: [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.05, green: 0.05, blue: 0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [accent.opacity(0.16), .clear], center: UnitPoint(x: 0.85, y: 0.15),
                               startRadius: 0, endRadius: 260)
            } else {
                LinearGradient(colors: [Color(red: 1, green: 1, blue: 0.99), Color(red: 0.955, green: 0.953, blue: 0.94)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(fg)
            Text(label).font(.system(size: 7.5, weight: .medium)).foregroundStyle(sub)
        }
    }

    private func chart(height: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(quarters.enumerated()), id: \.offset) { i, q in
                    let last = i == quarters.count - 1
                    VStack(spacing: 4) {
                        if last {
                            Text("$4.2M").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(accent)
                        }
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(last ? accent : faint)
                            .frame(height: height * q.1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(sub.opacity(0.35)).frame(height: 0.75)
            HStack(spacing: 10) {
                ForEach(Array(quarters.enumerated()), id: \.offset) { i, q in
                    Text(q.0).font(.system(size: 7.5, weight: i == quarters.count - 1 ? .semibold : .regular))
                        .foregroundStyle(i == quarters.count - 1 ? fg : sub)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
