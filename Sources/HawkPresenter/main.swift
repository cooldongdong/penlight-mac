import AppKit
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hid = PresenterHID()
    private var overlay: OverlayController!
    private lazy var hud = ModeHUD()
    private var menu: MenuController!
    private let router = KeyRouter()
    private let volumeKeys = VolumeKeys()
    private lazy var pie: PieMenu = {
        let p = PieMenu()
        p.onPick = { [weak self] mode in self?.switchMode(to: mode) }
        return p
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        menu = MenuController(overlay: overlay)

        // Reading the dongle's keyboard interface needs Input Monitoring.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        hid.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .holdBegan: self.overlay.show()
            case .holdEnded: self.stopAdjusting(); self.overlay.hide()
            case .adjustBegan(let bigger): self.startAdjusting(bigger: bigger)
            case .adjustEnded: self.stopAdjusting()
            case .volumeUpWhileHeld, .doubleTap: self.switchMode(to: self.overlay.settings.mode.next)
            case .volumeDownWhileHeld: self.switchMode(to: self.overlay.settings.mode.previous)
            case .gestureBegan: self.pie.begin()
            case .gestureEnded: self.pie.end()
            case .consumer(let usage): self.volumeKeys.consumer(usage)
            case .connected(let ok): self.menu.statusLine.title = ok ? "簡報筆：已連線" : "簡報筆：未連線"
            }
        }
        hid.start()

        volumeKeys.action = { [weak self] slot in self?.overlay.settings.action(for: slot) ?? slot.defaultAction }
        router.passVolumeToSystem = { [weak self] up in self?.volumeKeys.systemHandles(up: up) ?? true }
        router.lastPenKeyReport = { [weak self] in self?.hid.lastKeyReportAt ?? 0 }
        router.start() // asks for Accessibility the first time

        // `--demo magnifier` shows an effect for 8 s without the pen, for testing.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count,
           let mode = EffectMode.allCases.first(where: { "\($0)" == args[i + 1] }) {
            overlay.preview(mode: mode, for: 8)
        }
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
