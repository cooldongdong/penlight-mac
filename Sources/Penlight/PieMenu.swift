import AppKit

/// Four-way mode picker driven by the pen's gyro.
///
/// Double-tap the mode key and keep the second press held: the pie appears around
/// the cursor. Flick the pen toward a mode (the gyro moves the cursor), release to
/// pick it. The cursor is then put back where it started, so picking a mode never
/// moves the pointer. Releasing without leaving the centre cancels.
final class PieMenu {
    /// Direction → mode. Up is the most used one.
    static let layout: [(direction: Direction, mode: EffectMode)] = [
        (.up, .laser), (.right, .spotlight), (.down, .magnifier), (.left, .pointer),
    ]

    enum Direction { case up, right, down, left }

    var onPick: ((EffectMode) -> Void)?

    private let size: CGFloat = 320
    /// Cursor must travel this far from the centre before a slice is selected.
    private let deadZone: CGFloat = 45
    private let panel: NSPanel
    private let view: PieView
    private var anchor: NSPoint = .zero
    private var tracker: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        view = PieView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        panel.contentView = view
    }

    func begin() {
        anchor = NSEvent.mouseLocation
        view.selected = nil
        view.knob = .zero
        panel.setFrameOrigin(NSPoint(x: anchor.x - size / 2, y: anchor.y - size / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        SystemCursor.hide()
        tracker?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(t, forMode: .common)
        tracker = t
    }

    func end() {
        tracker?.invalidate(); tracker = nil
        let picked = view.selected
        panel.orderOut(nil)
        // Put the pointer back: the flick was only a gesture.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: anchor.x, y: mainHeight - anchor.y))
        SystemCursor.show()
        if let picked { onPick?(Self.layout.first { $0.direction == picked }!.mode) }
    }

    private func track() {
        let m = NSEvent.mouseLocation
        let dx = m.x - anchor.x, dy = m.y - anchor.y
        let dist = hypot(dx, dy)
        // Knob shows where the pen points, kept inside the ring.
        let maxKnob = size / 2 - 40
        let k = dist > maxKnob ? maxKnob / dist : 1
        view.knob = CGPoint(x: dx * k, y: dy * k)
        if dist < deadZone {
            view.selected = nil
        } else if abs(dx) > abs(dy) {
            view.selected = dx > 0 ? .right : .left
        } else {
            view.selected = dy > 0 ? .up : .down
        }
    }
}

private final class PieView: NSView {
    var selected: PieMenu.Direction? { didSet { if selected != oldValue { needsDisplay = true } } }
    var knob: CGPoint = .zero { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let outer = bounds.width / 2 - 4, inner: CGFloat = 38

        for (direction, mode) in PieMenu.layout {
            let mid: CGFloat = {
                switch direction { case .up: return 90; case .left: return 180; case .down: return 270; case .right: return 0 }
            }()
            let slice = NSBezierPath()
            slice.appendArc(withCenter: c, radius: outer, startAngle: mid - 44, endAngle: mid + 44)
            slice.appendArc(withCenter: c, radius: inner, startAngle: mid + 44, endAngle: mid - 44, clockwise: true)
            slice.close()
            let isOn = direction == selected
            (isOn ? NSColor.controlAccentColor.withAlphaComponent(0.9) : NSColor.black.withAlphaComponent(0.6)).setFill()
            slice.fill()

            let rad = mid * .pi / 180, r = (outer + inner) / 2
            let p = NSPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
            if let icon = NSImage(systemSymbolName: Self.symbol(mode), accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 26, weight: .semibold)) {
                let tinted = icon.tinted(.white)
                tinted.draw(in: NSRect(x: p.x - tinted.size.width / 2, y: p.y - 4, width: tinted.size.width, height: tinted.size.height))
            }
            let label = NSAttributedString(string: mode.title, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
            ])
            label.draw(at: NSPoint(x: p.x - label.size().width / 2, y: p.y - 26))
        }

        NSColor.white.setFill()
        let k = NSPoint(x: c.x + knob.x, y: c.y + knob.y)
        NSBezierPath(ovalIn: NSRect(x: k.x - 7, y: k.y - 7, width: 14, height: 14)).fill()
    }

    static func symbol(_ mode: EffectMode) -> String {
        switch mode {
        case .laser: return "smallcircle.filled.circle"
        case .spotlight: return "flashlight.on.fill"
        case .magnifier: return "plus.magnifyingglass"
        case .pointer: return "cursorarrow"
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
