import AppKit

enum OverlayKind: String, Codable {
    case line
    case circle
    case oval
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
    static let zoomPresets: [CGFloat] = [0.25, 0.50, 0.75, 1.0, 1.25, 1.50, 2.0, 4.0, 8.0, 16.0]
    static let rotationPresets = [0, 90, 180, 270]

    private let image: NSImage
    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var mapRotationDegrees = 0
    private var fogOfWarVisible = false
    private var fogOpeningCenter: CGPoint?
    private var fogOpeningDiameter: CGFloat?
    private var overlays: [AreaOverlay] = []
    private var selectedOverlayID: UUID?
    private var dragState: DragState?

    var profile: DocumentProfile {
        DocumentProfile(
            zoom: zoom,
            panOffset: panOffset,
            mapRotationDegrees: mapRotationDegrees,
            fogOfWarVisible: fogOfWarVisible,
            fogOpeningCenter: fogOpeningCenter,
            fogOpeningDiameter: fogOpeningDiameter,
            overlays: overlays
        )
    }

    var currentZoom: CGFloat { zoom }
    var currentMapRotationDegrees: Int { mapRotationDegrees }
    var isFogOfWarVisible: Bool { fogOfWarVisible }

    override var acceptsFirstResponder: Bool { true }

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
        mapRotationDegrees = Self.normalizedRotation(profile.mapRotationDegrees)
        fogOfWarVisible = profile.fogOfWarVisible
        fogOpeningCenter = profile.fogOpeningCenter
        fogOpeningDiameter = profile.fogOpeningDiameter
        overlays = profile.overlays
        selectedOverlayID = nil
        needsDisplay = true
    }

    func setZoom(_ magnification: CGFloat) {
        zoom = max(0.05, min(20.0, magnification))
        needsDisplay = true
    }

    func zoomInToNextPreset() -> Bool {
        guard let next = Self.zoomPresets.first(where: { $0 > zoom + 0.0001 }) else {
            NSSound.beep()
            return false
        }
        setZoom(next)
        return true
    }

    func zoomOutToNextPreset() -> Bool {
        guard let next = Self.zoomPresets.reversed().first(where: { $0 < zoom - 0.0001 }) else {
            NSSound.beep()
            return false
        }
        setZoom(next)
        return true
    }

    func setMapRotationDegrees(_ degrees: Int) {
        mapRotationDegrees = Self.normalizedRotation(degrees)
        needsDisplay = true
    }

    func toggleFogOfWar() {
        fogOfWarVisible.toggle()
        if fogOfWarVisible {
            ensureFogOpening()
        } else if case .moveFogOpening = dragState?.mode {
            dragState = nil
        }
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

    func selectedOverlayColor() -> OverlayColor? {
        guard let selectedOverlayID,
              let overlay = overlays.first(where: { $0.id == selectedOverlayID }) else {
            return nil
        }
        return overlay.color
    }

    func setSelectedOverlayColor(_ color: OverlayColor) {
        guard let selectedOverlayID,
              let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }) else {
            return
        }
        overlays[index].color = color
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
        context?.rotate(by: CGFloat(mapRotationDegrees) * .pi / 180.0)
        context?.translateBy(x: -image.size.width / 2.0, y: -image.size.height / 2.0)

        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1.0)
        drawOverlays()
        context?.restoreGState()

        drawFogOfWar()
    }

    override func scrollWheel(with event: NSEvent) {
        if isPowerMateHelperEvent(event) {
            panByScrollEvent(event)
            return
        }

        let cursor = convert(event.locationInWindow, from: nil)
        if fogGrayAreaContainsViewPoint(cursor) {
            resizeFogOpening(with: event)
            return
        }

        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        if let selectedOverlayID,
           let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }) {
            overlays[index].rotationRadians += delta * 0.015
            needsDisplay = true
            return
        }

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
        if fogGrayAreaContainsViewPoint(point) {
            selectedOverlayID = nil
            dragState = DragState(startViewPoint: point, startImagePoint: imagePoint, overlay: nil, mode: .moveFogOpening)
        } else if let hit = hitTestOverlay(at: imagePoint) {
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
        case .moveFogOpening:
            guard let center = fogOpeningCenter else { return }
            let delta = CGPoint(x: imagePoint.x - dragState.startImagePoint.x, y: imagePoint.y - dragState.startImagePoint.y)
            fogOpeningCenter = CGPoint(x: center.x + delta.x, y: center.y + delta.y)
            self.dragState?.startImagePoint = imagePoint
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
            if overlay.kind == .circle || overlay.kind == .cone {
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
            let fill = overlayColor.withAlphaComponent(0.20)
            let stroke = overlayColor
            let path = rotatedPath(for: overlay)

            if selected {
                drawSelectionShadow(for: path, color: overlayColor)
            } else {
                fill.setFill()
                stroke.setStroke()
                path.lineWidth = 2.0 / zoom
                path.fill()
                path.stroke()
            }

            if selected {
                let handlePath = NSBezierPath(rect: resizeHandleRect(for: overlay.rect))
                NSColor.white.setFill()
                handlePath.fill()
                NSColor.black.setStroke()
                handlePath.lineWidth = 1.0 / zoom
                handlePath.stroke()
            }
        }
    }

    private func drawFogOfWar() {
        guard fogOfWarVisible else { return }
        ensureFogOpening()
        guard let center = fogOpeningCenter,
              let diameter = fogOpeningDiameter else { return }

        let viewCenter = viewPoint(forImagePoint: center)
        let viewDiameter = max(1.0, diameter * zoom)
        let openingRect = CGRect(
            x: viewCenter.x - viewDiameter / 2.0,
            y: viewCenter.y - viewDiameter / 2.0,
            width: viewDiameter,
            height: viewDiameter
        )

        let path = NSBezierPath(rect: bounds)
        path.appendOval(in: openingRect)
        path.windingRule = .evenOdd
        NSColor(calibratedWhite: 0.38, alpha: 1.0).setFill()
        path.fill()

        NSColor(calibratedWhite: 0.82, alpha: 0.65).setStroke()
        let outline = NSBezierPath(ovalIn: openingRect)
        outline.lineWidth = 2.0
        outline.stroke()
    }

    private func overlayPath(for overlay: AreaOverlay) -> NSBezierPath {
        switch overlay.kind {
        case .line:
            let path = NSBezierPath()
            path.move(to: rotatedPoint(overlay.rect.origin, in: overlay))
            path.line(to: rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.maxY), in: overlay))
            path.lineWidth = 6.0 / zoom
            return path
        case .circle, .oval:
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

    private func drawSelectionShadow(for path: NSBezierPath, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            color.withAlphaComponent(0.20).setFill()
            color.setStroke()
            path.lineWidth = 2.0 / zoom
            path.fill()
            path.stroke()
            return
        }

        context.saveGState()
        let shadowColor = contrastShadowColor(for: color)
        context.setShadow(
            offset: .zero,
            blur: 28.0 / zoom,
            color: shadowColor.withAlphaComponent(1.0).cgColor
        )
        shadowColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 10.0 / zoom
        path.stroke()
        context.restoreGState()

        shadowColor.withAlphaComponent(0.70).setStroke()
        path.lineWidth = 5.0 / zoom
        path.stroke()

        color.withAlphaComponent(0.20).setFill()
        color.setStroke()
        path.lineWidth = 2.0 / zoom
        path.fill()
        path.stroke()
    }

    private func contrastShadowColor(for color: NSColor) -> NSColor {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = 0.299 * rgbColor.redComponent + 0.587 * rgbColor.greenComponent + 0.114 * rgbColor.blueComponent
        return luminance > 0.55 ? .black : .white
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
            resizeHandleRect(for: overlay.rect).insetBy(dx: -6.0 / zoom, dy: -6.0 / zoom).contains(point)
                || overlayContains(point, overlay: overlay)
        }
    }

    private func overlayContains(_ point: CGPoint, overlay: AreaOverlay) -> Bool {
        switch overlay.kind {
        case .line:
            let start = rotatedPoint(overlay.rect.origin, in: overlay)
            let end = rotatedPoint(CGPoint(x: overlay.rect.maxX, y: overlay.rect.maxY), in: overlay)
            return distance(from: point, toSegmentFrom: start, to: end) <= max(10.0 / zoom, 5.0)
        case .circle, .oval, .rectangle, .cone:
            let path = rotatedPath(for: overlay)
            if path.contains(point) {
                return true
            }
            path.lineWidth = max(10.0 / zoom, 5.0)
            return path.bounds.insetBy(dx: -path.lineWidth, dy: -path.lineWidth).contains(point)
        }
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let lengthSquared = dx * dx + dy * dy
        let t = max(0.0, min(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func resizeHandleRect(for rect: CGRect) -> CGRect {
        let size = max(8.0 / zoom, 4.0)
        return CGRect(x: rect.maxX - size / 2.0, y: rect.maxY - size / 2.0, width: size, height: size)
    }

    private func visibleImageRect() -> CGRect {
        let points = [
            imagePoint(forViewPoint: bounds.origin),
            imagePoint(forViewPoint: CGPoint(x: bounds.maxX, y: bounds.minY)),
            imagePoint(forViewPoint: CGPoint(x: bounds.minX, y: bounds.maxY)),
            imagePoint(forViewPoint: CGPoint(x: bounds.maxX, y: bounds.maxY))
        ]
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        let scaledPoint = CGPoint(
            x: (point.x - bounds.midX - panOffset.x) / zoom,
            y: (point.y - bounds.midY - panOffset.y) / zoom
        )
        let unrotated = rotate(scaledPoint, byDegrees: -mapRotationDegrees)
        return CGPoint(
            x: unrotated.x + image.size.width / 2.0,
            y: unrotated.y + image.size.height / 2.0
        )
    }

    private func viewPoint(forImagePoint point: CGPoint) -> CGPoint {
        let centered = CGPoint(
            x: point.x - image.size.width / 2.0,
            y: point.y - image.size.height / 2.0
        )
        let rotated = rotate(centered, byDegrees: mapRotationDegrees)
        return CGPoint(
            x: rotated.x * zoom + bounds.midX + panOffset.x,
            y: rotated.y * zoom + bounds.midY + panOffset.y
        )
    }

    private func ensureFogOpening() {
        if fogOpeningCenter == nil {
            fogOpeningCenter = imagePoint(forViewPoint: CGPoint(x: bounds.midX, y: bounds.midY))
        }
        if fogOpeningDiameter == nil || fogOpeningDiameter ?? 0 <= 0 {
            fogOpeningDiameter = defaultFogOpeningDiameter()
        }
    }

    private func defaultFogOpeningDiameter() -> CGFloat {
        let screenHeight = window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? bounds.height
        return max(20.0 / zoom, (screenHeight * 0.5) / max(zoom, 0.0001))
    }

    private func fogGrayAreaContainsViewPoint(_ point: CGPoint) -> Bool {
        guard fogOfWarVisible else { return false }
        ensureFogOpening()
        guard let center = fogOpeningCenter,
              let diameter = fogOpeningDiameter else { return false }
        let viewCenter = viewPoint(forImagePoint: center)
        let radius = diameter * zoom / 2.0
        let distance = hypot(point.x - viewCenter.x, point.y - viewCenter.y)
        return distance > radius
    }

    private func resizeFogOpening(with event: NSEvent) {
        ensureFogOpening()
        guard let diameter = fogOpeningDiameter else { return }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        let factor = pow(1.0045, delta)
        fogOpeningDiameter = max(20.0 / zoom, min(max(image.size.width, image.size.height) * 2.0, diameter * factor))
        needsDisplay = true
    }

    private func rotate(_ point: CGPoint, byDegrees degrees: Int) -> CGPoint {
        let radians = CGFloat(degrees) * .pi / 180.0
        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
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

    private static func normalizedRotation(_ degrees: Int) -> Int {
        let normalized = degrees % 360
        return normalized >= 0 ? normalized : normalized + 360
    }
}

private struct DragState {
    enum Mode {
        case moveFogOpening
        case pan
        case moveOverlay
        case resizeOverlay
    }

    var startViewPoint: CGPoint
    var startImagePoint: CGPoint
    let overlay: AreaOverlay?
    let mode: Mode
}
