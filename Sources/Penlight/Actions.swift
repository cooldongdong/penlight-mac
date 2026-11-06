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
    case systemVolume   // volume keys only: leave the key alone, macOS changes the volume
    case nothing
    case click
    case missionControl
    case blackScreen
    case mode(EffectMode)
    case shortcut(KeyCombo?)

    /// Choices offered in pickers (the shortcut entry stands for "record one").
    static func choices(includeVolume: Bool) -> [PenAction] {
        (includeVolume ? [.systemVolume] : [])
            + [.nothing, .click, .missionControl, .blackScreen]
            + EffectMode.allCases.map { .mode($0) }
            + [.shortcut(nil)]
    }

    var title: String {
        switch self {
        case .systemVolume: return "調整音量（系統預設）"
        case .nothing: return "不做事"
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
        case .systemVolume: return "speaker.wave.2"
        case .nothing: return "circle.slash"
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
    /// Set by the app: how to switch the effect mode.
    static var switchMode: ((EffectMode) -> Void)?

    static func perform(_ action: PenAction, volumeUp: Bool = true) {
        switch action {
        case .nothing: break
        case .systemVolume: postVolumeKey(up: volumeUp)
        case .click: click()
        case .blackScreen: press(keyCode: CGKeyCode(kVK_ANSI_B), flags: [])
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

/// Every assignable place: four volume-key presses and four pie slices.
enum KeySlot: String, CaseIterable {
    case volumeUpShort, volumeUpLong, volumeDownShort, volumeDownLong
    case pieUp, pieRight, pieDown, pieLeft

    static let volumeSlots: [KeySlot] = [.volumeUpShort, .volumeUpLong, .volumeDownShort, .volumeDownLong]
    static let pieSlots: [KeySlot] = [.pieUp, .pieRight, .pieDown, .pieLeft]
    var isVolume: Bool { Self.volumeSlots.contains(self) }

    var title: String {
        switch self {
        case .volumeUpShort: return "音量 + 短按"
        case .volumeUpLong: return "音量 + 長按"
        case .volumeDownShort: return "音量 − 短按"
        case .volumeDownLong: return "音量 − 長按"
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
