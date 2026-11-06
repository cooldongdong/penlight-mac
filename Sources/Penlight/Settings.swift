import AppKit
import Combine

/// Shared, adjustable look of every effect. Every change is saved to UserDefaults
/// and published, so the overlay and the SwiftUI panels stay in sync.
final class EffectSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: EffectMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    /// Temporary, unsaved override used by previews (e.g. while dragging a slider).
    var previewMode: EffectMode?
    var activeMode: EffectMode { previewMode ?? mode }
    @Published var laserColor: NSColor { didSet { defaults.set(laserColor.hexRGB, forKey: "laserColor") } }
    @Published var laserRadius: CGFloat { didSet { save(laserRadius, "laserRadius") } }
    @Published var spotlightRadius: CGFloat { didSet { save(spotlightRadius, "spotlightRadius") } }
    /// 0 = no dimming, 1 = black.
    @Published var spotlightDim: CGFloat { didSet { save(spotlightDim, "spotlightDim") } }
    @Published var lensRadius: CGFloat { didSet { save(lensRadius, "lensRadius") } }
    @Published var zoom: CGFloat { didSet { save(zoom, "zoom") } }
    @Published var pointerHaloRadius: CGFloat { didSet { save(pointerHaloRadius, "pointerHaloRadius") } }
    /// Flash the new mode's name in the middle of the screen after switching.
    /// Laser drawn as the user's own image instead of the dot.
    @Published var useLaserImage: Bool { didSet { defaults.set(useLaserImage, forKey: "useLaserImage") } }
    @Published private(set) var laserImage: NSImage?
    /// Image mode: its own picture, shown much larger than the laser.
    @Published private(set) var stampImage: NSImage?
    @Published var imageModeSize: CGFloat { didSet { save(imageModeSize, "imageModeSize") } }
    @Published var showModeHUD: Bool { didSet { defaults.set(showModeHUD, forKey: "showModeHUD") } }
    /// Multiplier for the pen's gyro motion only (Mac trackpad / mouse unaffected).
    @Published var pointerSpeed: CGFloat { didSet { save(pointerSpeed, "pointerSpeed") } }

    var isPresetColor: Bool { Self.laserPresets.contains { $0.1.hexRGB == laserColor.hexRGB } }

    /// Seven rainbow hues spaced far apart so no two read alike, at a brightness
    /// that shows on both light and dark slides (the dot keeps a white core and glow).
    static let laserPresets: [(String, NSColor)] = [
        ("紅", NSColor(hexRGB: "FF3B30")!), ("橙", NSColor(hexRGB: "FF9500")!),
        ("黃", NSColor(hexRGB: "FFD60A")!), ("綠", NSColor(hexRGB: "30D158")!),
        ("青", NSColor(hexRGB: "40C8E0")!), ("藍", NSColor(hexRGB: "0A84FF")!),
        ("紫", NSColor(hexRGB: "BF5AF2")!),
    ]

    init() {
        mode = EffectMode(rawValue: UserDefaults.standard.integer(forKey: "mode")) ?? .laser
        laserColor = (UserDefaults.standard.string(forKey: "laserColor")).flatMap(NSColor.init(hexRGB:)) ?? .systemRed
        let d = UserDefaults.standard
        func load(_ key: String, _ fallback: CGFloat) -> CGFloat {
            d.object(forKey: key) == nil ? fallback : CGFloat(d.double(forKey: key))
        }
        laserRadius = load("laserRadius", 14)
        spotlightRadius = load("spotlightRadius", 180)
        spotlightDim = load("spotlightDim", 0.75)
        lensRadius = load("lensRadius", 170)
        zoom = load("zoom", 2)
        pointerHaloRadius = load("pointerHaloRadius", 30)
        showModeHUD = d.bool(forKey: "showModeHUD") // off unless turned on
        pointerSpeed = load("pointerSpeed", 1)
        useLaserImage = d.bool(forKey: "useLaserImage")
        laserImage = NSImage(contentsOf: Self.laserImageURL)
        stampImage = NSImage(contentsOf: Self.imageURL("stamp.png"))
        imageModeSize = load("imageModeSize", 240)
    }

    private func save(_ v: CGFloat, _ key: String) { defaults.set(Double(v), forKey: key) }

    /// Our own copy, so moving or deleting the original doesn't break the pointer.
    static func imageURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Penlight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
    static var laserImageURL: URL { imageURL("pointer.png") }

    enum ImageSlot { case laser, stamp }

    /// Copies the picked file as PNG into our folder. Returns false if unreadable.
    @discardableResult
    func setImage(_ slot: ImageSlot, from url: URL) -> Bool {
        let dest = slot == .laser ? Self.laserImageURL : Self.imageURL("stamp.png")
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              (try? png.write(to: dest)) != nil else { return false }
        switch slot {
        case .laser:
            laserImage = NSImage(contentsOf: dest)
            useLaserImage = true
        case .stamp:
            stampImage = NSImage(contentsOf: dest)
        }
        return true
    }

    func action(for slot: KeySlot) -> PenAction {
        PenAction.decode(defaults.object(forKey: "slot." + slot.rawValue)) ?? slot.defaultAction
    }

    func setAction(_ action: PenAction, for slot: KeySlot) {
        objectWillChange.send()
        defaults.set(action.encoded, forKey: "slot." + slot.rawValue)
    }

    /// Page up / page down while holding the mode key. `steps` may be fractional
    /// (continuous adjustment while the key is held).
    func adjust(bigger: Bool, steps: CGFloat = 1) {
        let s = (bigger ? 1 : -1) * steps
        switch mode {
        case .laser: laserRadius = (laserRadius + 4 * s).clamped(6, 60)
        case .spotlight: spotlightRadius = (spotlightRadius + 30 * s).clamped(60, 600)
        case .magnifier: zoom = (zoom + 0.5 * s).clamped(1.5, 5)
        case .pointer: pointerHaloRadius = (pointerHaloRadius + 6 * s).clamped(16, 90)
        case .image: imageModeSize = (imageModeSize + 60 * s).clamped(60, 900) // big steps
        }
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

extension NSColor {
    var hexRGB: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    convenience init?(hexRGB s: String) {
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
