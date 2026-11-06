import AppKit
import SwiftUI

/// Menu-bar icon. Click → panel; the panel's "設定…" opens the Settings window.
final class StatusController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settingsWindow: SettingsWindowController

    init(settings: EffectSettings, state: AppState, overlay: OverlayController) {
        settingsWindow = SettingsWindowController(settings: settings, state: state)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "laser.burst", accessibilityDescription: "Penlight")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        // Semi-transient: stays open while the colour panel (our own window) is used,
        // closes when clicking anywhere outside Penlight.
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PanelView(
            settings: settings, state: state,
            onPreview: { [weak overlay] mode in overlay?.preview(mode: mode, for: 1.2) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenPermissions: { [weak self] in self?.openSettings(.permissions) }
        ))
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openSettings(_ tab: SettingsWindowController.Tab? = nil) {
        popover.performClose(nil)
        settingsWindow.show(tab)
    }
}
