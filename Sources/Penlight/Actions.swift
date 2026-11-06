import AppKit

/// Things a pen key can be assigned to. Kept as one catalogue so that later every
/// key (and every pie slice) can pick from the same list.
enum PenAction: String, CaseIterable {
    case systemVolume   // leave the key alone: macOS changes the volume
    case nothing
    case click
    case missionControl

    var title: String {
        switch self {
        case .systemVolume: return "調整音量（系統預設）"
        case .nothing: return "不做事"
        case .click: return "滑鼠點擊（開超連結）"
        case .missionControl: return "指揮中心（切換視窗）"
        }
    }
}

/// Tag on events we synthesise, so our own event tap lets them through.
let syntheticEventTag: Int64 = 0x4841574B // "HAWK"

enum ActionRunner {
    static func perform(_ action: PenAction, volumeUp: Bool) {
        switch action {
        case .nothing: break
        case .systemVolume: postVolumeKey(up: volumeUp)
        case .click: click()
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

/// The four volume-key slots. Each can hold any `PenAction`.
enum KeySlot: String, CaseIterable {
    case volumeUpShort, volumeUpLong, volumeDownShort, volumeDownLong

    var title: String {
        switch self {
        case .volumeUpShort: return "音量 + 短按"
        case .volumeUpLong: return "音量 + 長按"
        case .volumeDownShort: return "音量 − 短按"
        case .volumeDownLong: return "音量 − 長按"
        }
    }

    var defaultAction: PenAction {
        switch self {
        case .volumeUpShort: return .click
        case .volumeDownShort: return .missionControl
        case .volumeUpLong, .volumeDownLong: return .nothing
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
