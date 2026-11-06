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
    private let speedSlider = NSSlider(value: 1, minValue: 0.3, maxValue: 3, target: nil, action: nil)
    private var previewWork: DispatchWorkItem?
    private var actionItems: [NSMenuItem] = []
    private let accessibilityItem = NSMenuItem(title: "", action: #selector(openAccessibility), keyEquivalent: "")
    private let hudItem = NSMenuItem(title: "切換時顯示模式名稱", action: #selector(toggleHUD), keyEquivalent: "")

    init(overlay: OverlayController) {
        self.overlay = overlay
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "laser.burst", accessibilityDescription: "Hawk Presenter")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(header("模式（按住模式鍵＋音量鍵切換）"))
        for mode in EffectMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            modeItems.append(item)
            menu.addItem(item)
        }
        hudItem.target = self
        menu.addItem(hudItem)
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

        menu.addItem(header("簡報筆指標速度（左慢 → 右快）"))
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.isContinuous = true
        let speedHolder = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        speedSlider.frame = NSRect(x: 18, y: 4, width: 190, height: 20)
        speedHolder.addSubview(speedSlider)
        let speedItem = NSMenuItem()
        speedItem.view = speedHolder
        menu.addItem(speedItem)

        menu.addItem(.separator())
        let keysRoot = NSMenuItem(title: "簡報筆音量鍵", action: nil, keyEquivalent: "")
        let keysMenu = NSMenu()
        for slot in KeySlot.allCases {
            let slotItem = NSMenuItem(title: slot.title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for action in PenAction.allCases {
                let item = NSMenuItem(title: action.title, action: #selector(pickAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [slot.rawValue, action.rawValue]
                sub.addItem(item)
                actionItems.append(item)
            }
            slotItem.submenu = sub
            keysMenu.addItem(slotItem)
        }
        keysMenu.addItem(.separator())
        keysMenu.addItem(accessibilityItem)
        accessibilityItem.target = self
        keysRoot.submenu = keysMenu
        menu.addItem(keysRoot)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        modeItems.forEach { $0.state = $0.tag == settings.mode.rawValue ? .on : .off }
        let hex = settings.laserColor.hexRGB
        colorItems.forEach { $0.state = EffectSettings.laserPresets[$0.tag].1.hexRGB == hex ? .on : .off }
        dimSlider.doubleValue = Double(settings.spotlightDim)
        speedSlider.doubleValue = Double(settings.pointerSpeed)
        hudItem.state = settings.showModeHUD ? .on : .off
        for item in actionItems {
            guard let pair = item.representedObject as? [String],
                  let slot = KeySlot(rawValue: pair[0]) else { continue }
            item.state = settings.action(for: slot).rawValue == pair[1] ? .on : .off
        }
        accessibilityItem.title = KeyRouter.isTrusted ? "輔助使用權限：已允許" : "輔助使用權限：尚未允許（點此開啟設定）"
        accessibilityItem.isEnabled = !KeyRouter.isTrusted
    }

    @objc private func pickAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String],
              let slot = KeySlot(rawValue: pair[0]), let action = PenAction(rawValue: pair[1]) else { return }
        settings.setAction(action, for: slot)
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func speedChanged() { settings.pointerSpeed = CGFloat(speedSlider.doubleValue) }

    @objc private func toggleHUD() { settings.showModeHUD.toggle() }

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
