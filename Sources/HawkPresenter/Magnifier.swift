import AppKit
import ScreenCaptureKit
import CoreMedia

/// Streams the display under the cursor (excluding our own overlay windows) and hands
/// each frame's IOSurface to `onFrame`. Runs only while magnifier mode is selected.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((IOSurface) -> Void)?
    private var stream: SCStream?
    private(set) var displayID: CGDirectDisplayID?
    private let queue = DispatchQueue(label: "hawk.capture")

    /// Starts (or restarts) streaming the given display. Safe to call repeatedly.
    func start(displayID id: CGDirectDisplayID) {
        if displayID == id, stream != nil { return }
        stop()
        displayID = id
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self, let content else {
                NSLog("HawkPresenter: screen capture unavailable: %@", String(describing: error))
                return
            }
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

            let scale = CGFloat(CGDisplayPixelsWide(id)) / CGFloat(display.width)
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * max(scale, 1))
            config.height = Int(CGFloat(display.height) * max(scale, 1))
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = false
            config.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
            } catch {
                NSLog("HawkPresenter: addStreamOutput failed: %@", String(describing: error)); return
            }
            stream.startCapture { error in
                if let error { NSLog("HawkPresenter: startCapture failed: %@", String(describing: error)) }
            }
            DispatchQueue.main.async { self.stream = stream }
        }
    }

    func stop() {
        stream?.stopCapture(completionHandler: nil)
        stream = nil
        displayID = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        let s = unsafeBitCast(surface, to: IOSurface.self)
        DispatchQueue.main.async { self.onFrame?(s) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("HawkPresenter: stream stopped: %@", String(describing: error))
        DispatchQueue.main.async { if self.stream === stream { self.stream = nil; self.displayID = nil } }
    }
}

/// Round lens layer showing a zoomed crop of the latest frame around the cursor.
final class LensLayer: CALayer {
    override init() {
        super.init()
        masksToBounds = true
        borderWidth = 3
        borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        backgroundColor = NSColor.black.cgColor
        contentsGravity = .resize
        actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "contentsRect": NSNull()]
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    /// - Parameters:
    ///   - point: cursor in the host view (bottom-left origin, points)
    ///   - viewSize: host view size in points (= screen size)
    func place(at point: NSPoint, viewSize: CGSize, radius: CGFloat, zoom: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        cornerRadius = radius
        position = point
        // Portion of the screen to show, in the unit space of the captured frame.
        // On macOS that space starts at the bottom-left, same as the view.
        let w = (radius * 2 / zoom) / viewSize.width
        let h = (radius * 2 / zoom) / viewSize.height
        contentsRect = CGRect(x: point.x / viewSize.width - w / 2,
                              y: point.y / viewSize.height - h / 2, width: w, height: h)
    }
}
