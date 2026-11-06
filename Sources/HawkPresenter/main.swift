import AppKit
import IOKit.hid

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hid = PresenterHID()
    private var overlay: OverlayController!
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
            case .pageUpWhileHeld: self.overlay.radius = min(self.overlay.radius + 4, 60)
            case .pageDownWhileHeld: self.overlay.radius = max(self.overlay.radius - 4, 6)
            case .doubleTap: break // mode cycling comes in the next version
            case .connected(let ok): self.statusLine.title = ok ? "簡報筆：已連線" : "簡報筆：未連線"
            }
        }
        hid.start()
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
