import AppKit

/// Menu-bar menu: connection status, current mode, laser colour, spotlight dimming.
final class MenuController: NSObject, NSMenuDelegate {
    let statusLine = NSMenuItem(title: "簡報筆：尋找中…", action: nil, keyEquivalent: "")
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay: OverlayController
    private var settings: EffectSettings { overlay.settings }
    private var modeItems: [NSMenuItem] = []
    private var colorItems: [NSMenuItem] = []
    private let dimSlider = NSSlider(value: 0.75, minValue: 0.2, maxValue: 0.95, target: nil, action: nil)
    private var previewWork: DispatchWorkItem?

    init(overlay: OverlayController) {
        self.overlay = overlay
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "laser.burst", accessibilityDescription: "Hawk Presenter")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(header("模式（連按兩下模式鍵切換）"))
        for mode in EffectMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            modeItems.append(item)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let colorMenu = NSMenu()
        for (i, (name, color)) in EffectSettings.laserPresets.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.image = swatch(color)
            colorItems.append(item)
            colorMenu.addItem(item)
        }
        colorMenu.addItem(.separator())
        let custom = NSMenuItem(title: "自訂顏色…", action: #selector(customColor), keyEquivalent: "")
        custom.target = self
        colorMenu.addItem(custom)
        let colorRoot = NSMenuItem(title: "雷射點顏色", action: nil, keyEquivalent: "")
        colorRoot.submenu = colorMenu
        menu.addItem(colorRoot)

        menu.addItem(header("聚光燈背景（左亮 → 右暗）"))
        dimSlider.target = self
        dimSlider.action = #selector(dimChanged)
        dimSlider.isContinuous = true
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        dimSlider.frame = NSRect(x: 18, y: 4, width: 190, height: 20)
        holder.addSubview(dimSlider)
        let sliderItem = NSMenuItem()
        sliderItem.view = holder
        menu.addItem(sliderItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        modeItems.forEach { $0.state = $0.tag == settings.mode.rawValue ? .on : .off }
        let hex = settings.laserColor.hexRGB
        colorItems.forEach { $0.state = EffectSettings.laserPresets[$0.tag].1.hexRGB == hex ? .on : .off }
        dimSlider.doubleValue = Double(settings.spotlightDim)
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        settings.mode = EffectMode(rawValue: sender.tag) ?? .laser
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        settings.laserColor = EffectSettings.laserPresets[sender.tag].1
    }

    @objc private func customColor() {
        let panel = NSColorPanel.shared
        panel.color = settings.laserColor
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        settings.laserColor = panel.color
    }

    /// Dragging the slider previews the spotlight briefly so the darkness can be judged.
    @objc private func dimChanged() {
        settings.spotlightDim = CGFloat(dimSlider.doubleValue)
        overlay.preview(mode: .spotlight, for: 1.2)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
