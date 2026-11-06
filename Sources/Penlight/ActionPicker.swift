import AppKit
import SwiftUI

/// Picks the action of one slot. Choosing "自訂快捷鍵…" reveals a recorder.
struct ActionPicker: View {
    @ObservedObject var settings: EffectSettings
    let slot: KeySlot
    var showsLabel = true
    /// Pie tab: fixed-width picker with the recorder underneath, so nothing moves sideways.
    var compactWidth: CGFloat? = nil
    /// Keys tab: fixed picker width with a fixed slot for the recorder on its right.
    var inline: (picker: CGFloat, recorder: CGFloat)? = nil

    private var current: PenAction { settings.action(for: slot) }

    var body: some View {
        if let inline {
            HStack(spacing: 8) {
                picker.frame(width: inline.picker)
                Group {
                    if case .shortcut(let combo) = current {
                        ShortcutRecorder(combo: combo) { settings.setAction(.shortcut($0), for: slot) }
                    } else {
                        Color.clear
                    }
                }
                .frame(width: inline.recorder, height: 22)
            }
        } else if let w = compactWidth {
            VStack(spacing: 6) {
                picker.frame(width: w)
                // Always reserve the recorder's row so choosing "shortcut" doesn't shift anything.
                Group {
                    if case .shortcut(let combo) = current {
                        ShortcutRecorder(combo: combo) { settings.setAction(.shortcut($0), for: slot) }
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 22)
            }
        } else {
            HStack(spacing: 8) {
                picker
                if case .shortcut(let combo) = current {
                    ShortcutRecorder(combo: combo) { settings.setAction(.shortcut($0), for: slot) }
                }
            }
        }
    }

    private var picker: some View {
            Picker(showsLabel ? slot.title : "", selection: Binding(
                get: { current.choiceKey },
                set: { choice in
                    // Re-picking "shortcut" keeps an already recorded combo.
                    if case .shortcut = choice, case .shortcut = current { return }
                    settings.setAction(choice, for: slot)
                }
            )) {
                ForEach(PenAction.choices(for: slot), id: \.self) { action in
                    Label(action.title, systemImage: action.symbol).tag(action)
                }
            }
            .labelsHidden(!showsLabel)
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { self.labelsHidden() } else { self }
    }
}

/// Click, then press a key combination. Esc cancels.
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onRecord: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "請按下按鍵…" : (combo?.display ?? "錄製")) {
            recording ? stop() : start()
        }
        .frame(minWidth: 74)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            onRecord(KeyCombo(keyCode: event.keyCode, modifiers: mods.rawValue,
                              display: KeyCombo.describe(mods, key: Self.keyName(event))))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func keyName(_ e: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "空白", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let s = special[e.keyCode] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
