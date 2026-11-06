import AppKit
import Carbon.HIToolbox

/// A recorded key combination, e.g. ⌘⇧4.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, device-independent bits only.
    var modifiers: UInt
    /// What the user saw when recording, e.g. "⌘⇧4".
    var display: String

    var cgFlags: CGEventFlags {
        let m = NSEvent.ModifierFlags(rawValue: modifiers)
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        return f
    }

    static func describe(_ m: NSEvent.ModifierFlags, key: String) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s + key
    }
}

/// Things a pen key or a pie slice can do. One catalogue shared by every slot.
enum PenAction: Codable, Hashable {
    /// Leave the key alone: whatever the pen normally does (page, volume, slideshow…).
    /// Named systemVolume for compatibility with stored settings.
    case systemVolume
    case nothing
    case pageUp, pageDown
    case nextMode, previousMode
    /// Bigger / smaller for the current effect; continuous while held when assigned
    /// to "hold mode key + page up/down".
    case grow, shrink
    case click
    case missionControl
    case blackScreen
    case mode(EffectMode)
    case shortcut(KeyCombo?)

    /// Choices offered in pickers (the shortcut entry stands for "record one").
    static func choices(for slot: KeySlot) -> [PenAction] {
        let all: [PenAction] = [.nothing, .click, .missionControl, .blackScreen, .pageUp, .pageDown]
            + [.nextMode, .previousMode, .grow, .shrink]
            + EffectMode.allCases.map { .mode($0) }
            + [.shortcut(nil)]
        guard let native = slot.nativeTitle else { return all }
        // The key's own function goes first, under its real name; don't list it twice.
        return [.systemVolume] + all.filter { $0.title != native }
    }

    /// Symbol as shown for a given slot (the key's own function gets its own icon).
    func symbol(for slot: KeySlot) -> String {
        guard case .systemVolume = self else { return symbol }
        switch slot {
        case .pageUpShort: return "chevron.up"
        case .pageDownShort: return "chevron.down"
        case .pageUpLong: return "play.rectangle"
        case .pageDownLong: return "rectangle.fill"
        case .volumeUpShort, .volumeUpLong: return "speaker.wave.3"
        case .volumeDownShort, .volumeDownLong: return "speaker.wave.1"
        default: return symbol
        }
    }

    /// Title as shown for a given slot: "keep the key's own function" reads as that function.
    func title(for slot: KeySlot) -> String {
        if case .systemVolume = self, let native = slot.nativeTitle { return native }
        return title
    }

    var title: String {
        switch self {
        case .systemVolume: return "原本的功能"
        case .nothing: return "不做事"
        case .pageUp: return "上一頁"
        case .pageDown: return "下一頁"
        case .nextMode: return "下一個模式"
        case .previousMode: return "上一個模式"
        case .grow: return "效果放大"
        case .shrink: return "效果縮小"
        case .click: return "滑鼠點擊"
        case .missionControl: return "指揮中心"
        case .blackScreen: return "黑屏"
        case .mode(let m): return "切換到\(m.title)"
        case .shortcut(let combo): return combo.map { "快捷鍵 \($0.display)" } ?? "自訂快捷鍵…"
        }
    }

    /// Short label for the pie slice.
    var shortTitle: String {
        switch self {
        case .mode(let m): return m.title
        case .shortcut(let combo): return combo?.display ?? "快捷鍵"
        case .missionControl: return "指揮中心"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .systemVolume: return "arrow.uturn.backward"
        case .nothing: return "circle.slash"
        case .pageUp: return "chevron.up"
        case .pageDown: return "chevron.down"
        case .nextMode: return "arrow.right.circle"
        case .previousMode: return "arrow.left.circle"
        case .grow: return "plus.circle"
        case .shrink: return "minus.circle"
        case .click: return "cursorarrow.click"
        case .missionControl: return "rectangle.3.group"
        case .blackScreen: return "rectangle.fill"
        case .mode(let m): return m.symbol
        case .shortcut: return "command"
        }
    }

    /// Picker identity: every recorded shortcut matches the single "shortcut" choice.
    var choiceKey: PenAction {
        if case .shortcut = self { return .shortcut(nil) }
        return self
    }

    // Stored as JSON. Older builds stored a bare raw string ("click"); still read those.
    static func decode(_ stored: Any?) -> PenAction? {
        if let data = stored as? Data { return try? JSONDecoder().decode(PenAction.self, from: data) }
        switch stored as? String {
        case "systemVolume": return .systemVolume
        case "nothing": return .nothing
        case "click": return .click
        case "missionControl": return .missionControl
        default: return nil
        }
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

/// Tag on events we synthesise, so our own event tap lets them through.
let syntheticEventTag: Int64 = 0x4841574B // "HAWK"

enum ActionRunner {
    /// Set by the app: how to switch the effect mode, cycle it, and resize it.
    static var switchMode: ((EffectMode) -> Void)?
    static var cycleMode: ((_ forward: Bool) -> Void)?
    static var resize: ((_ bigger: Bool) -> Void)?

    static func perform(_ action: PenAction, volumeUp: Bool = true) {
        switch action {
        case .nothing: break
        case .systemVolume: postVolumeKey(up: volumeUp)
        case .click: click()
        case .blackScreen: press(keyCode: CGKeyCode(kVK_ANSI_B), flags: [])
        case .pageUp: press(keyCode: CGKeyCode(kVK_PageUp), flags: [])
        case .pageDown: press(keyCode: CGKeyCode(kVK_PageDown), flags: [])
        case .nextMode: cycleMode?(true)
        case .previousMode: cycleMode?(false)
        case .grow: resize?(true)
        case .shrink: resize?(false)
        case .mode(let m): switchMode?(m)
        case .shortcut(let combo):
            if let combo { press(keyCode: CGKeyCode(combo.keyCode), flags: combo.cgFlags) }
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        }
    }

    /// Left click at the current cursor position (needs Accessibility).
    static func click() {
        guard let loc = CGEvent(source: nil)?.location else { return }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: loc, mouseButton: .left)
            e?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Press a key combination, e.g. ⌘Return (needs Accessibility).
    static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Re-create a volume key press when we swallowed one but the slot says "volume".
    static func postVolumeKey(up: Bool) {
        let key = up ? 0 : 1 // NX_KEYTYPE_SOUND_UP / NX_KEYTYPE_SOUND_DOWN
        for down in [true, false] {
            let data1 = (key << 16) | ((down ? 0x0A : 0x0B) << 8)
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            let cg = ev?.cgEvent
            cg?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            cg?.post(tap: .cghidEventTap)
        }
    }
}

/// Every assignable place on the pen, plus the four pie slices.
enum KeySlot: String, CaseIterable {
    case pageUpShort, pageUpLong, pageDownShort, pageDownLong
    case volumeUpShort, volumeUpLong, volumeDownShort, volumeDownLong
    case modeTap, modeDoubleTap, modeHoldVolumeUp, modeHoldVolumeDown, modeHoldPageUp, modeHoldPageDown
    case pieUp, pieRight, pieDown, pieLeft

    /// What the pen does by itself in this slot, by name; nil when there's nothing to keep.
    var nativeTitle: String? {
        switch self {
        case .pageUpShort: return "上一頁"
        case .pageDownShort: return "下一頁"
        case .pageUpLong: return "開始／結束放映"
        case .pageDownLong: return "黑屏"
        case .volumeUpShort, .volumeUpLong: return "調高音量"
        case .volumeDownShort, .volumeDownLong: return "調低音量"
        default: return nil
        }
    }

    static let volumeSlots: [KeySlot] = [.volumeUpShort, .volumeUpLong, .volumeDownShort, .volumeDownLong]
    static let pieSlots: [KeySlot] = [.pieUp, .pieRight, .pieDown, .pieLeft]
    var isVolume: Bool { Self.volumeSlots.contains(self) }

    var title: String {
        switch self {
        case .volumeUpShort, .volumeDownShort: return "短按"
        case .volumeUpLong, .volumeDownLong: return "長按"
        case .pageUpShort, .pageDownShort: return "短按"
        case .pageUpLong, .pageDownLong: return "長按"
        case .modeTap: return "輕按"
        case .modeDoubleTap: return "連按兩下"
        case .modeHoldVolumeUp: return "按住 ＋ 音量 ＋"
        case .modeHoldVolumeDown: return "按住 ＋ 音量 −"
        case .modeHoldPageUp: return "按住 ＋ 上一頁"
        case .modeHoldPageDown: return "按住 ＋ 下一頁"
        case .pieUp: return "上"
        case .pieRight: return "右"
        case .pieDown: return "下"
        case .pieLeft: return "左"
        }
    }

    var defaultAction: PenAction {
        switch self {
        case .volumeUpShort: return .click
        case .volumeDownShort: return .missionControl
        case .volumeUpLong, .volumeDownLong: return .nothing
        case .pageUpShort, .pageUpLong, .pageDownShort, .pageDownLong: return .systemVolume
        case .modeTap: return .nothing
        case .modeDoubleTap, .modeHoldVolumeUp: return .nextMode
        case .modeHoldVolumeDown: return .previousMode
        case .modeHoldPageUp: return .grow
        case .modeHoldPageDown: return .shrink
        case .pieUp: return .mode(.laser)
        case .pieRight: return .mode(.spotlight)
        case .pieDown: return .mode(.magnifier)
        case .pieLeft: return .mode(.pointer)
        }
    }

    static func slots(up: Bool) -> (short: KeySlot, long: KeySlot) {
        up ? (.volumeUpShort, .volumeUpLong) : (.volumeDownShort, .volumeDownLong)
    }
}

/// Turns the pen's volume-key HID reports into short / long press actions.
final class VolumeKeys {
    var action: (KeySlot) -> PenAction = { $0.defaultAction }
    private let longPress: TimeInterval = 0.6
    private var pressed: Bool? // up?
    private var longFired = false
    private var longTimer: DispatchWorkItem?

    /// The system keeps the key only when both of its slots are "volume".
    func systemHandles(up: Bool) -> Bool {
        let s = KeySlot.slots(up: up)
        return action(s.short) == .systemVolume && action(s.long) == .systemVolume
    }

    /// `usage`: 0xE9 volume up, 0xEA volume down, 0 released.
    func consumer(_ usage: UInt16) {
        switch usage {
        case 0xE9, 0xEA:
            let up = usage == 0xE9
            guard pressed == nil, !systemHandles(up: up) else { return }
            pressed = up
            longFired = false
            let slots = KeySlot.slots(up: up)
            guard action(slots.long) != .nothing else { return } // no long action: always short
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.longFired = true
                ActionRunner.perform(self.action(slots.long), volumeUp: up)
            }
            longTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + longPress, execute: work)
        case 0:
            guard let up = pressed else { return }
            pressed = nil
            longTimer?.cancel(); longTimer = nil
            if !longFired { ActionRunner.perform(action(KeySlot.slots(up: up).short), volumeUp: up) }
        default: break
        }
    }
}

/// The physical buttons, for the device diagram in Settings.
enum PenButton: CaseIterable {
    case mode, pageUp, pageDown, laser, volumeUp, volumeDown

    var title: String {
        switch self {
        case .mode: return "模式鍵"
        case .pageUp: return "上一頁"
        case .pageDown: return "下一頁"
        case .laser: return "雷射鍵"
        case .volumeUp: return "音量 ＋"
        case .volumeDown: return "音量 −"
        }
    }

    var slots: [KeySlot] {
        switch self {
        case .mode: return [.modeTap, .modeDoubleTap, .modeHoldVolumeUp, .modeHoldVolumeDown, .modeHoldPageUp, .modeHoldPageDown]
        case .pageUp: return [.pageUpShort, .pageUpLong]
        case .pageDown: return [.pageDownShort, .pageDownLong]
        case .laser: return []
        case .volumeUp: return [.volumeUpShort, .volumeUpLong]
        case .volumeDown: return [.volumeDownShort, .volumeDownLong]
        }
    }

    /// What can't be changed, said once under the slots.
    var note: String? {
        switch self {
        case .mode: return "輕按：半秒內放開、不移動筆（一碰就放開收不到）。按住與圓形選單固定不變。"
        case .pageUp, .pageDown: return nil
        case .laser: return "雷射鍵只發出實體綠光，不會傳訊號給電腦，所以無法自訂。"
        case .volumeUp, .volumeDown: return nil
        }
    }
}
