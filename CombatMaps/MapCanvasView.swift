import AppKit

enum OverlayKind: String, Codable {
    case line
    case circle
    case rectangle
    case cone
}

struct AreaOverlay: Codable, Identifiable {
    var id = UUID()
    var kind: OverlayKind
    var rect: CGRect
    var color: OverlayColor = .systemTeal
    var rotationRadians: CGFloat = 0
}

struct OverlayColor: Codable {
    static let systemTeal = OverlayColor(.systemTeal)

    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? .systemTeal
        red = rgbColor.redComponent
        green = rgbColor.greenComponent
        blue = rgbColor.blueComponent
        alpha = rgbColor.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }
}

final class MapCanvasView: NSView {
    private let image: NSImage
    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var overlays: [AreaOverlay] = []
    private var selectedOverlayID: UUID?
    private var dragState: DragState?

    var profile: DocumentProfile {
        DocumentProfile(zoom: zoom, panOffset: panOffset)
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        postsFrameChangedNotifications = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(profile: DocumentProfile) {
        zoom = max(0.05, min(20.0, profile.zoom))
        panOffset = profile.panOffset
        needsDisplay = true
    }

    func addOverlay(kind: OverlayKind, color: OverlayColor) {
        window?.makeFirstResponder(self)
        let imageRect = visibleImageRect()
        let side = min(imageRect.width, imageRect.height) * 0.25
        let origin = CGPoint(x: imageRect.midX - side / 2.0, y: imageRect.midY - side / 2.0)
        let overlay = AreaOverlay(kind: kind, rect: CGRect(origin: origin, size: CGSize(width: side, height: side)), color: color)
        overlays.append(overlay)
        selectedOverlayID = overlay.id
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard image.size.width > 0, image.size.height > 0 else { return }
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.translateBy(x: bounds.midX + panOffset.x, y: bounds.midY + panOffset.y)
        context?.scaleBy(x: zoom, y: zoom)
        context?.translateBy(x: -image.size.width / 2.0, y: -image.size.height / 2.0)

        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1.0)
        drawOverlays()
        context?.restoreGState()
    }

    override func scrollWheel(with event: NSEvent) {
        if isPowerMateHelperEvent(event) {
            panByScrollEvent(event)
            return
        }

        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        if let selectedOverlayID,
           let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }) {
            overlays[index].rotationRadians += delta * 0.015
            needsDisplay = true
            return
        }

        let cursor = convert(event.locationInWindow, from: nil)
        let before = imagePoint(forViewPoint: cursor)
        let factor = pow(1.0045, delta)
        zoom = max(0.05, min(20.0, zoom * factor))
        let after = viewPoint(forImagePoint: before)
        panOffset.x += cursor.x - after.x
        panOffset.y += cursor.y - after.y
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = imagePoint(forViewPoint: point)
        if let hit = hitTestOverlay(at: imagePoint) {
            selectedOverlayID = hit.id
            let resize = resizeHandleRect(for: hit.rect).contains(imagePoint)
            dragState = DragState(startViewPoint: point, startImagePoint: imagePoint, overlay: hit, mode: resize ? .resizeOverlay : .moveOverlay)
        } else {
            selectedOverlayID = nil
            dragState = DragState(startViewPoint: point, startImagePoint: imagePoint, overlay: nil, mode: .pan)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragState else { return }
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = imagePoint(forViewPoint: point)
        switch dragState.mode {
        case .pan:
            panOffset.x += point.x - dragState.startViewPoint.x
            panOffset.y += point.y - dragState.startViewPoint.y
            self.dragState?.startViewPoint = point
        case .moveOverlay:
            guard let overlay = dragState.overlay,
                  let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
            let delta = CGPoint(x: imagePoint.x - dragState.startImagePoint.x, y: imagePoint.y - dragState.startImagePoint.y)
            let movedRect = overlay.rect.offsetBy(dx: delta.x, dy: delta.y)
            overlays[index].rect = clampedOverlayRect(movedRect)
        case .resizeOverlay:
            guard let overlay = dragState.overlay,
                  let index = overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
            let minSide: CGFloat = 8.0
            let width = max(minSide, imagePoint.x - overlay.rect.minX)
            let height = max(minSide, imagePoint.y - overlay.rect.minY)
            if overlay.kind == .cone {
                let side = max(width, height)
                overlays[index].rect = clampedOverlayRect(CGRect(x: overlay.rect.minX, y: overlay.rect.minY, width: side, height: side))
            } else {
                overlays[index].rect = clampedOverlayRect(CGRect(x: overlay.rect.minX, y: overlay.rect.minY, width: width, height: height))
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragState = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51, let selectedOverlayID {
            overlays.removeAll { $0.id == selectedOverlayID }
            self.selectedOverlayID = nil
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private func drawOverlays() {
        for overlay in overlays {
            let selected = overlay.id == selectedOverlayID
            let overlayColor = overlay.color.nsColor
            let fill = overlayColor.withAlphaComponent(selected ? 0.30 : 0.20)
            let stroke = selected ? NSColor.white : overlayColor
            let path = rotatedPath(for: overlay)
            fill.setFill()
            stroke.setStroke()
            path.lineWidth = 2.0 / zoom
            path.fill()
            path.stroke()

            if selected {
                NSColor.white.setFill()
                resizeHandleRect(for: overlay.rect).fill()
            }
        }
    }

    private func overlayPath(for overlay: AreaOverlay) -> NSBezierPath {
        switch overlay.kind {
        case .line:
            let path = NSBezierPath()
            path.move(to: rotatedPoint(overlay.rect.origin, in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.maxY), in: overlay))
            path.lineWidth = 6.0 / zoom
            return path
        case .circle:
            return NSBezierPath(ovalIn: overlay.rect)
        case .rectangle:
            let path = NSBezierPath()
            path.move(to: rotatedPoint(CGPoint(x: overlay.rect.minX, y: overlay.rect.minY), in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.minY), in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.maxY), in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.minX, y: overlay.rect.maxY), in: overlay))
            path.close()
            return path
        case .cone:
            let path = NSBezierPath()
            path.move(to: rotatedPoint(CGPoint(x: overlay.rect.midX, y: overlay.rect.minY), in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.maxY), in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.minX, y: overlay.rect.maxY), in: overlay))
            path.close()
            return path
        }
    }

    private func rotatedPath(for overlay: AreaOverlay) -> NSBezierPath {
        overlayPath(for: overlay)
    }

    private func rotatedPoint(_ point: CGPoint, in overlay: AreaOverlay) -> CGPoint {
        guard overlay.rotationRadians != 0 else { return point }
        let center = CGPoint(x: overlay.rect.midX, y: overlay.rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosine = cos(overlay.rotationRadians)
        let sine = sin(overlay.rotationRadians)
        return CGPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }

    private func clampedOverlayRect(_ rect: CGRect) -> CGRect {
        let visibleRect = visibleImageRect().intersection(CGRect(origin: .zero, size: image.size))
        guard visibleRect.isNull == false, visibleRect.isEmpty == false else {
            return rect
        }

        let minimumVisible = max(24.0 / zoom, 12.0)
        var clamped = rect
        clamped.origin.x = min(clamped.origin.x, visibleRect.maxX - minimumVisible)
        clamped.origin.y = min(clamped.origin.y, visibleRect.maxY - minimumVisible)
        clamped.origin.x = max(clamped.origin.x, visibleRect.minX - clamped.width + minimumVisible)
        clamped.origin.y = max(clamped.origin.y, visibleRect.minY - clamped.height + minimumVisible)
        return clamped
    }

    private func hitTestOverlay(at point: CGPoint) -> AreaOverlay? {
        overlays.reversed().first { overlay in
            overlay.rect.insetBy(dx: -8.0 / zoom, dy: -8.0 / zoom).contains(point)
        }
    }

    private func resizeHandleRect(for rect: CGRect) -> CGRect {
        let size = max(8.0 / zoom, 4.0)
        return CGRect(x: rect.maxX - size / 2.0, y: rect.maxY - size / 2.0, width: size, height: size)
    }

    private func visibleImageRect() -> CGRect {
        let topLeft = imagePoint(forViewPoint: bounds.origin)
        let bottomRight = imagePoint(forViewPoint: CGPoint(x: bounds.maxX, y: bounds.maxY))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    private func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - bounds.midX - panOffset.x) / zoom + image.size.width / 2.0,
            y: (point.y - bounds.midY - panOffset.y) / zoom + image.size.height / 2.0
        )
    }

    private func viewPoint(forImagePoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - image.size.width / 2.0) * zoom + bounds.midX + panOffset.x,
            y: (point.y - image.size.height / 2.0) * zoom + bounds.midY + panOffset.y
        )
    }

    private func panByScrollEvent(_ event: NSEvent) {
        panOffset.x += event.scrollingDeltaX * 12.0
        panOffset.y += event.scrollingDeltaY * 12.0
        needsDisplay = true
    }

    private func isPowerMateHelperEvent(_ event: NSEvent) -> Bool {
        guard let pid = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID),
              pid > 0,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
            return false
        }

        let appName = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        return appName.contains("powermate") || bundleID.contains("powermate")
    }
}

private struct DragState {
    enum Mode {
        case pan
        case moveOverlay
        case resizeOverlay
    }

    var startViewPoint: CGPoint
    let startImagePoint: CGPoint
    let overlay: AreaOverlay?
    let mode: Mode
}
