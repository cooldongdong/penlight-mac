import AppKit

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

/// Draws the digital laser dot at the given point (view coordinates).
final class LaserView: NSView {
    var point: NSPoint? { didSet { needsDisplay = true } }
    var color: NSColor = .systemRed
    var radius: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        guard let p = point else { return }
        let glow = radius * 2.2
        let ctx = NSGraphicsContext.current!.cgContext
        let colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: p, startRadius: radius * 0.6,
                               endCenter: p, endRadius: glow, options: [])
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)).fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        let core = radius * 0.35
        NSBezierPath(ovalIn: NSRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)).fill()
    }
}

/// One overlay per screen; shows the effect on whichever screen the cursor is on.
final class OverlayController {
    private var windows: [(NSScreen, OverlayWindow, LaserView)] = []
    private var tracker: Timer?

    var radius: CGFloat = 14 { didSet { windows.forEach { $0.2.radius = radius; $0.2.needsDisplay = true } } }

    init() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
    }

    private func rebuild() {
        windows.forEach { $0.1.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let view = LaserView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.radius = radius
            return (screen, OverlayWindow(screen: screen, view: view), view)
        }
    }

    func show() {
        windows.forEach { $0.1.orderFrontRegardless() }
        tracker?.invalidate()
        tracker = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tracker!, forMode: .common)
        update()
    }

    func hide() {
        tracker?.invalidate(); tracker = nil
        windows.forEach { $0.2.point = nil; $0.1.orderOut(nil) }
    }

    private func update() {
        let mouse = NSEvent.mouseLocation // global, bottom-left origin
        for (screen, _, view) in windows {
            if screen.frame.contains(mouse) {
                view.point = NSPoint(x: mouse.x - screen.frame.minX, y: mouse.y - screen.frame.minY)
            } else if view.point != nil {
                view.point = nil
            }
        }
    }
}
