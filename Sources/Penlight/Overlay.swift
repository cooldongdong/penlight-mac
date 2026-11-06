import AppKit
import Combine

enum EffectMode: Int, CaseIterable, Codable {
    case laser, spotlight, magnifier, pointer, image

    var title: String {
        switch self {
        case .laser: return "雷射點"
        case .spotlight: return "聚光燈"
        case .magnifier: return "放大鏡"
        case .pointer: return "滑鼠"
        case .image: return "圖片"
        }
    }

    /// SF Symbol shared by the pie menu and the menu-bar panel.
    var symbol: String {
        switch self {
        case .laser: return "smallcircle.filled.circle"
        case .spotlight: return "flashlight.on.fill"
        case .magnifier: return "plus.magnifyingglass"
        case .pointer: return "cursorarrow"
        case .image: return "photo"
        }
    }

    /// Modes that keep the real cursor visible (so links show the hand cursor).
    var showsSystemCursor: Bool { self == .pointer }

    var next: EffectMode { EffectMode(rawValue: (rawValue + 1) % EffectMode.allCases.count)! }
    var previous: EffectMode {
        let n = EffectMode.allCases.count
        return EffectMode(rawValue: (rawValue + n - 1) % n)!
    }
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

final class EffectView: NSView {
    let settings: EffectSettings
    /// Cursor position in view coordinates, or nil when the cursor is on another screen.
    var point: NSPoint? { didSet { needsDisplay = true } }

    let lens = LensLayer()

    init(frame: NSRect, settings: EffectSettings) {
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true
        lens.isHidden = true
        layer!.addSublayer(lens)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        switch settings.activeMode {
        case .laser: drawLaser()
        case .spotlight: drawSpotlight()
        case .magnifier: break // drawn by `lens`
        case .pointer: drawPointerHalo()
        case .image: drawImageMode()
        }
        updateLens()
    }

    func updateLens() {
        guard settings.activeMode == .magnifier, let p = point else { lens.isHidden = true; return }
        lens.isHidden = false
        lens.place(at: p, viewSize: bounds.size, radius: settings.lensRadius, zoom: settings.zoom)
    }

    private func drawLaser() {
        guard let p = point else { return }
        if settings.useLaserImage, let image = settings.laserImage {
            // Centred on the cursor, fitted into a square that the page keys resize.
            let box = settings.laserRadius * 3
            let s = image.size, k = min(box / max(s.width, 1), box / max(s.height, 1))
            let w = s.width * k, h = s.height * k
            image.draw(in: NSRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h))
            return
        }
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

    /// A big picture at the cursor (logo, sticker…); placeholder until one is chosen.
    private func drawImageMode() {
        guard let p = point else { return }
        let box = settings.imageModeSize
        guard let image = settings.stampImage else {
            let rect = NSRect(x: p.x - box / 2, y: p.y - box / 2, width: box, height: box)
            let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            path.setLineDash([8, 6], count: 2, phase: 0)
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.7).setStroke()
            path.stroke()
            let text = NSAttributedString(string: "在 Penlight 設定裡選一張圖", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white,
            ])
            text.draw(at: NSPoint(x: p.x - text.size().width / 2, y: p.y - text.size().height / 2))
            return
        }
        let s = image.size, k = min(box / max(s.width, 1), box / max(s.height, 1))
        image.draw(in: NSRect(x: p.x - s.width * k / 2, y: p.y - s.height * k / 2, width: s.width * k, height: s.height * k))
    }

    /// Soft ring around the real cursor so the audience can find it.
    private func drawPointerHalo() {
        guard let p = point else { return }
        let r = settings.pointerHaloRadius
        let ring = NSBezierPath(ovalIn: circle(p, r))
        settings.laserColor.withAlphaComponent(0.18).setFill()
        ring.fill()
        settings.laserColor.withAlphaComponent(0.7).setStroke()
        ring.lineWidth = 3
        ring.stroke()
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
    private let streamer = ScreenStreamer()
    private var stopStreamWork: DispatchWorkItem?

    private var settingsChange: AnyCancellable?

    init() {
        rebuild()
        // Any setting changed (panel, pen, settings window) → redraw on the next turn.
        settingsChange = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.redraw(); self?.windows.forEach { $0.view.updateLens() } }
        }
        streamer.onFrame = { [weak self] surface in
            guard let self else { return }
            for w in self.windows where w.screen.displayID == self.streamer.displayID {
                w.view.lens.contents = surface
            }
        }
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

    private var previewEnd: DispatchWorkItem?

    /// Shows `mode` for a moment without changing the saved mode or hiding the cursor.
    /// Ignored while the pen is actually holding an effect.
    func preview(mode: EffectMode, for seconds: TimeInterval) {
        if isShowing && settings.previewMode == nil { return }
        settings.previewMode = mode
        show(hideCursor: false)
        previewEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settings.previewMode != nil else { return }
            self.hide()
        }
        previewEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func show(hideCursor: Bool = true) {
        if hideCursor { settings.previewMode = nil; previewEnd?.cancel() } // real hold wins over a preview
        isShowing = true
        if hideCursor && !settings.activeMode.showsSystemCursor { SystemCursor.hide() }
        redraw()
        windows.forEach { $0.window.orderFrontRegardless() }
        tracker?.invalidate()
        tracker = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tracker!, forMode: .common)
        update()
    }

    func hide() {
        isShowing = false
        settings.previewMode = nil
        SystemCursor.show()
        tracker?.invalidate(); tracker = nil
        windows.forEach { $0.view.point = nil; $0.window.orderOut(nil) }
        // Keep capturing a few seconds so the next hold shows the lens instantly,
        // then stop so the screen-recording indicator goes away.
        stopStreamWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.streamer.stop() }
        stopStreamWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func redraw() { windows.forEach { $0.view.needsDisplay = true } }

    /// Call after switching mode while the effect is on screen.
    func modeChanged() {
        if isShowing && settings.previewMode == nil {
            settings.activeMode.showsSystemCursor ? SystemCursor.show() : SystemCursor.hide()
        }
        redraw()
        windows.forEach { $0.view.updateLens() }
    }

    private func update() {
        let mouse = NSEvent.mouseLocation // global, bottom-left origin
        for w in windows {
            let p: NSPoint? = w.screen.frame.contains(mouse)
                ? NSPoint(x: mouse.x - w.screen.frame.minX, y: mouse.y - w.screen.frame.minY) : nil
            if p != w.view.point { w.view.point = p }
            if p != nil, settings.activeMode == .magnifier, let id = w.screen.displayID {
                stopStreamWork?.cancel()
                streamer.start(displayID: id)
            }
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

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
