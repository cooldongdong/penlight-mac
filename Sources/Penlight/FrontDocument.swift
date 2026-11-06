import AppKit
import ApplicationServices

/// What the frontmost window is showing, read through the Accessibility API
/// (window titles from CGWindowList get truncated by some browsers, e.g. Dia).
enum FrontDocument {
    /// Title of the focused window of the frontmost app.
    static func title() -> String? {
        guard let win = focusedWindow() else { return nil }
        return string(win, kAXTitleAttribute)
    }

    /// URL of the web page in the focused window, if the app exposes one
    /// (AXDocument on the window, or AXURL on the first web area).
    static func url() -> String? {
        guard let win = focusedWindow() else { return nil }
        if let doc = string(win, kAXDocumentAttribute) { return doc }
        return findWebAreaURL(win, depth: 0)
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success else { return nil }
        return (win as! AXUIElement)
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        if let s = v as? String { return s }
        if let u = v as? URL { return u.absoluteString }
        return nil
    }

    private static func findWebAreaURL(_ el: AXUIElement, depth: Int) -> String? {
        guard depth < 8 else { return nil }
        if string(el, kAXRoleAttribute) == "AXWebArea" {
            return string(el, kAXURLAttribute)
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return nil }
        for child in list.prefix(40) {
            if let u = findWebAreaURL(child, depth: depth + 1) { return u }
        }
        return nil
    }
}
