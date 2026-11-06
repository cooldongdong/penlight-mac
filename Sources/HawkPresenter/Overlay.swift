import AppKit

enum EffectMode: Int, CaseIterable {
    case laser, spotlight

    var title: String {
        switch self {
        case .laser: return "雷射點"
        case .spotlight: return "聚光燈"
        }
    }

    var next: EffectMode { EffectMode(rawValue: (rawValue + 1) % EffectMode.allCases.count)! }
}

/// Transparent, click-through window covering one screen, drawn above everything
/// (including full-screen Keynote / PowerPoint slideshows).
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
        setFrame(screen.frame, display: false)
    }
}

/// Shared, adjustable look of every effect.
final class EffectSettings {
    var mode: EffectMode = .laser
    var laserColor: NSColor = .systemRed
    var laserRadius: CGFloat = 14
    var spotlightRadius: CGFloat = 180
    var spotlightDim: CGFloat = 0.75

    /// Page up / page down while holding the mode key.
    func adjust(bigger: Bool) {
        switch mode {
        case .laser:
            laserRadius = (laserRadius + (bigger ? 4 : -4)).clamped(6, 60)
        case .spotlight:
            spotlightRadius = (spotlightRadius + (bigger ? 30 : -30)).clamped(60, 600)
        }
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

final class EffectView: NSView {
    let settings: EffectSettings
    /// Cursor position in view coordinates, or nil when the cursor is on another screen.
    var point: NSPoint? { didSet { needsDisplay = true } }

    init(frame: NSRect, settings: EffectSettings) {
        self.settings = settings
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        switch settings.mode {
        case .laser: drawLaser()
        case .spotlight: drawSpotlight()
        }
    }

    private func drawLaser() {
        guard let p = point else { return }
        let r = settings.laserRadius, color = settings.laserColor
        let ctx = NSGraphicsContext.current!.cgContext
        let colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: p, startRadius: r * 0.6, endCenter: p, endRadius: r * 2.2, options: [])
        color.setFill()
        NSBezierPath(ovalIn: circle(p, r)).fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: circle(p, r * 0.35)).fill()
    }

    private func drawSpotlight() {
        // Screens without the cursor are dimmed completely, so the audience looks at one spot.
        let path = NSBezierPath(rect: bounds)
        if let p = point {
            path.append(NSBezierPath(ovalIn: circle(p, settings.spotlightRadius)))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(settings.spotlightDim).setFill()
        path.fill()
        if let p = point {
            NSColor.white.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: circle(p, settings.spotlightRadius))
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    private func circle(_ p: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    }
}

/// One overlay per screen; follows the cursor while the effect is shown.
final class OverlayController {
    let settings = EffectSettings()
    private var windows: [(screen: NSScreen, window: OverlayWindow, view: EffectView)] = []
    private var tracker: Timer?
    private(set) var isShowing = false

    init() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
    }

    private func rebuild() {
        windows.forEach { $0.window.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let view = EffectView(frame: NSRect(origin: .zero, size: screen.frame.size), settings: settings)
            return (screen, OverlayWindow(screen: screen, view: view), view)
        }
        if isShowing { windows.forEach { $0.window.orderFrontRegardless() } }
    }

    func show() {
        isShowing = true
        windows.forEach { $0.window.orderFrontRegardless() }
        tracker?.invalidate()
        tracker = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tracker!, forMode: .common)
        update()
    }

    func hide() {
        isShowing = false
        tracker?.invalidate(); tracker = nil
        windows.forEach { $0.view.point = nil; $0.window.orderOut(nil) }
    }

    func redraw() { windows.forEach { $0.view.needsDisplay = true } }

    private func update() {
        let mouse = NSEvent.mouseLocation // global, bottom-left origin
        for w in windows {
            let p: NSPoint? = w.screen.frame.contains(mouse)
                ? NSPoint(x: mouse.x - w.screen.frame.minX, y: mouse.y - w.screen.frame.minY) : nil
            if p != w.view.point { w.view.point = p }
        }
    }
}

/// Brief "雷射點 / 聚光燈" label in the middle of the cursor's screen after switching mode.
final class ModeHUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 84),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 18
        bg.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(bg)

        label.font = .systemFont(ofSize: 30, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 22, width: 220, height: 40)
        panel.contentView!.addSubview(label)
    }

    func flash(_ text: String) {
        label.stringValue = text
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let f = panel.frame
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - f.width / 2, y: screen.frame.midY - f.height / 2))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self?.panel.animator().alphaValue = 0 },
                                                 completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
