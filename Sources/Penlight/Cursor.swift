import AppKit

// Private CoreGraphics Services API. A background (accessory) app may not hide the
// cursor unless its connection sets "SetsCursorInBackground". Widely used by
// presenter/screen tools; the original Hawk app does the same ("hackMouseCursor").
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32

@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ targetCID: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// Balanced hide/show of the system cursor. CGDisplayHideCursor is reference
/// counted, so we track our own state and never hide twice.
enum SystemCursor {
    private static var hidden = false
    private static var enabled = false

    private static func enableBackgroundControl() {
        guard !enabled else { return }
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        enabled = true
    }

    static func hide() {
        guard !hidden else { return }
        enableBackgroundControl()
        CGDisplayHideCursor(CGMainDisplayID())
        hidden = true
    }

    static func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}
