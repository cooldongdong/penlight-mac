import AppKit
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hid = PresenterHID()
    private var overlay: OverlayController!
    private lazy var hud = ModeHUD()
    private let state = AppState()
    private var status: StatusController!
    private lazy var onboarding = OnboardingWindowController(state: state)
    private let router = KeyRouter()
    private let volumeKeys = VolumeKeys()
    private lazy var pie: PieMenu = {
        let p = PieMenu()
        p.actionFor = { [weak self] slot in self?.overlay.settings.action(for: slot) ?? slot.defaultAction }
        p.onPick = { action in ActionRunner.perform(action) }
        return p
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        status = StatusController(settings: overlay.settings, state: state, overlay: overlay)
        // Permissions are asked for by the onboarding window, not by surprise prompts.
        if !state.allGranted || CommandLine.arguments.contains("--onboarding") { onboarding.show() }

        hid.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .holdBegan:
                self.holdStart = (Date(), NSEvent.mouseLocation)
                self.holdCombined = false
                self.overlay.show()
            case .holdEnded:
                self.stopAdjusting()
                self.overlay.hide()
                self.fireTapIfQuick()
            case .adjustBegan(let bigger):
                self.holdCombined = true
                // Grow/shrink keep their continuous behaviour; anything else fires once.
                let action = self.action(bigger ? .modeHoldPageUp : .modeHoldPageDown)
                switch action {
                case .grow: self.startAdjusting(bigger: true)
                case .shrink: self.startAdjusting(bigger: false)
                default: ActionRunner.perform(action)
                }
            case .adjustEnded: self.stopAdjusting()
            case .doubleTap: ActionRunner.perform(self.action(.modeDoubleTap))
            case .volumeUpWhileHeld: self.holdCombined = true; ActionRunner.perform(self.action(.modeHoldVolumeUp))
            case .volumeDownWhileHeld: self.holdCombined = true; ActionRunner.perform(self.action(.modeHoldVolumeDown))
            case .gestureBegan: self.pie.begin()
            case .gestureEnded: self.pie.end()
            case .consumer(let usage): self.volumeKeys.consumer(usage)
            case .connected(let ok): self.state.penConnected = ok
            }
        }
        hid.start()

        ActionRunner.switchMode = { [weak self] mode in self?.switchMode(to: mode) }
        ActionRunner.cycleMode = { [weak self] forward in
            guard let self else { return }
            let m = self.overlay.settings.mode
            self.switchMode(to: forward ? m.next : m.previous)
        }
        ActionRunner.resize = { [weak self] bigger in
            self?.overlay.settings.adjust(bigger: bigger)
            self?.overlay.redraw()
        }
        router.actionFor = { [weak self] slot in self?.action(slot) ?? slot.defaultAction }
        volumeKeys.action = { [weak self] slot in self?.overlay.settings.action(for: slot) ?? slot.defaultAction }
        router.passVolumeToSystem = { [weak self] up in self?.volumeKeys.systemHandles(up: up) ?? true }
        router.lastPenKeyReport = { [weak self] in self?.hid.lastKeyReportAt ?? 0 }
        // Pen-only pointer speed: once we may post events, take over the pen's mouse.
        hid.onMouseDelta = { [weak self] dx, dy in self?.movePointer(dx: dx, dy: dy) }
        router.onInstalled = { [weak self] in self?.hid.seizeMouse(true) }
        router.start() // asks for Accessibility the first time

        // `--demo magnifier` shows an effect for 8 s without the pen, for testing.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count,
           let mode = EffectMode.allCases.first(where: { "\($0)" == args[i + 1] }) {
            overlay.preview(mode: mode, for: 8)
        }
        // `--settings <0-3>` opens the Settings window on a tab, for screenshots.
        if let i = args.firstIndex(of: "--settings"), i + 1 < args.count,
           let n = Int(args[i + 1]), let tab = SettingsWindowController.Tab(rawValue: n) {
            status.openSettings(tab)
        }
    }

    /// Move the cursor by the pen's motion × speed. Small motions are kept precise,
    /// fast flicks get boosted, roughly like the system's own acceleration.
    /// Runs on the mouse thread, not the main thread.
    private var pointerRemainder = CGPoint.zero

    private func movePointer(dx: Int, dy: Int) {
        guard var loc = CGEvent(source: nil)?.location else { return }
        let speed = overlay.settings.pointerSpeed
        let mag = hypot(CGFloat(dx), CGFloat(dy))
        let gain = speed * (1.3 + min(mag, 24) * 0.12)
        let mx = CGFloat(dx) * gain + pointerRemainder.x
        let my = CGFloat(dy) * gain + pointerRemainder.y
        pointerRemainder = CGPoint(x: mx - mx.rounded(.towardZero), y: my - my.rounded(.towardZero))
        loc.x += mx.rounded(.towardZero)
        loc.y += my.rounded(.towardZero)
        loc = Self.clampToDisplays(loc)
        let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: loc, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(mx.rounded(.towardZero)))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(my.rounded(.towardZero)))
        e?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        e?.post(tap: .cghidEventTap)
    }

    /// Keep a point (global, top-left origin) on some display.
    private static func clampToDisplays(_ p: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        // Nearest point on the nearest display.
        let clamped = rects.map { r in
            CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
        }
        return clamped.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? p
    }

    private func action(_ slot: KeySlot) -> PenAction { overlay.settings.action(for: slot) }

    // MARK: Light tap on the mode key
    //
    // A truly short press sends nothing at all (measured 2026-11-07, unfiltered).
    // A slightly longer one sends a brief "held", so a short hold without moving
    // the pen and without other keys counts as a tap. The effect flashes briefly;
    // delaying every hold instead would make the normal hold feel laggy.

    private var holdStart: (time: Date, location: NSPoint)?
    private var holdCombined = false
    private let tapMaxDuration: TimeInterval = 0.6
    private let tapMaxTravel: CGFloat = 12

    private func fireTapIfQuick() {
        guard let start = holdStart else { return }
        holdStart = nil
        let action = self.action(.modeTap)
        guard action != .nothing, !holdCombined,
              Date().timeIntervalSince(start.time) < tapMaxDuration else { return }
        let end = NSEvent.mouseLocation
        guard hypot(end.x - start.location.x, end.y - start.location.y) < tapMaxTravel else { return }
        ActionRunner.perform(action)
    }

    private func switchMode(to mode: EffectMode) {
        overlay.settings.mode = mode
        overlay.modeChanged()
        if overlay.settings.showModeHUD { hud.flash(mode.title) }
    }

    // MARK: Page up/down while holding: one step on press, then continuous while held.

    private var adjustTimer: Timer?
    private var adjustDelay: DispatchWorkItem?

    private func startAdjusting(bigger: Bool) {
        stopAdjusting()
        overlay.settings.adjust(bigger: bigger)
        overlay.redraw()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let fps = 60.0, stepsPerSecond = 4.0
            let timer = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
                self?.overlay.settings.adjust(bigger: bigger, steps: CGFloat(stepsPerSecond / fps))
                self?.overlay.redraw()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.adjustTimer = timer
        }
        adjustDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func stopAdjusting() {
        adjustDelay?.cancel(); adjustDelay = nil
        adjustTimer?.invalidate(); adjustTimer = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemCursor.show() // never leave the user without a cursor
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
