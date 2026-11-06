import AppKit
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hid = PresenterHID()
    private var overlay: OverlayController!
    private lazy var hud = ModeHUD()
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "簡報筆：尋找中…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        setUpMenu()

        // Reading the dongle's keyboard interface needs Input Monitoring.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        hid.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .holdBegan: self.overlay.show()
            case .holdEnded: self.overlay.hide()
            case .pageUpWhileHeld: self.overlay.settings.adjust(bigger: true); self.overlay.redraw()
            case .pageDownWhileHeld: self.overlay.settings.adjust(bigger: false); self.overlay.redraw()
            case .doubleTap:
                self.overlay.settings.mode = self.overlay.settings.mode.next
                self.overlay.redraw()
                self.hud.flash(self.overlay.settings.mode.title)
            case .connected(let ok): self.statusLine.title = ok ? "簡報筆：已連線" : "簡報筆：未連線"
            }
        }
        hid.start()

        // `--demo magnifier` shows an effect for 8 s without the pen, for testing.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count,
           let mode = EffectMode.allCases.first(where: { "\($0)" == args[i + 1] }) {
            overlay.settings.mode = mode
            overlay.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.overlay.hide() }
        }
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laser.burst", accessibilityDescription: "Hawk Presenter")
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
