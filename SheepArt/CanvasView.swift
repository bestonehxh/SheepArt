import AppKit
import SwiftUI
import Combine

// MARK: - The AppKit canvas: draws in image space, converts on the fly

final class CanvasNSView: NSView {
    var document: CanvasDocument? {
        didSet {
            guard document !== oldValue else { return }
            cancellable = document?.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.needsDisplay = true }
            }
            needsDisplay = true
        }
    }

    private var cancellable: AnyCancellable?

    override var isFlipped: Bool { true }          // +y down, same as image space
    override var acceptsFirstResponder: Bool { true }

    // View-space placement of the canvas, recomputed every draw.
    private var scale: CGFloat = 1
    private var canvasOrigin = CGPoint.zero

    private enum Handle: Equatable {
        case start, end          // line / arrow endpoints
        case corner(Int)         // 0 tl, 1 tm, 2 tr, 3 ml, 4 mr, 5 bl, 6 bm, 7 br
    }

    private enum DragState {
        case none
        case creating(UUID)
        case moving(UUID, last: CGPoint, pushed: Bool)
        case resizing(UUID, Handle, pushed: Bool)
        case cropNew(anchor: CGPoint)
        case cropMove(last: CGPoint)
        case cropResize(Handle)
    }

    private var drag: DragState = .none

    // MARK: Coordinate mapping

    private func layoutCanvas() {
        guard let size = document?.canvasSize, size.width > 0, size.height > 0 else { return }
        let pad: CGFloat = 28
        let availW = max(bounds.width - pad * 2, 50)
        let availH = max(bounds.height - pad * 2, 50)
        scale = min(1, min(availW / size.width, availH / size.height))
        let w = size.width * scale, h = size.height * scale
        canvasOrigin = CGPoint(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2)
        if let doc = document, abs(doc.displayScale - scale) > 0.001 {
            let s = scale
            DispatchQueue.main.async { doc.displayScale = s }
        }
    }

    private func toImage(_ p: NSPoint) -> CGPoint {
        CGPoint(x: (p.x - canvasOrigin.x) / scale, y: (p.y - canvasOrigin.y) / scale)
    }

    private func toView(_ p: CGPoint) -> NSPoint {
        NSPoint(x: canvasOrigin.x + p.x * scale, y: canvasOrigin.y + p.y * scale)
    }

    private func toView(_ r: CGRect) -> NSRect {
        NSRect(x: canvasOrigin.x + r.origin.x * scale, y: canvasOrigin.y + r.origin.y * scale,
               width: r.width * scale, height: r.height * scale)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let doc = document, let size = doc.canvasSize else { return }
        layoutCanvas()

        let canvasRect = toView(CGRect(origin: .zero, size: size))

        // Canvas backing card with a soft shadow
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.set()
        NSColor.white.setFill()
        canvasRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Objects, clipped to the canvas, drawn in image space
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: canvasRect).addClip()
        let t = NSAffineTransform()
        t.translateX(by: canvasOrigin.x, yBy: canvasOrigin.y)
        t.scaleX(by: scale, yBy: scale)
        t.concat()
        ObjectRenderer.draw(doc.objects) { doc.image(for: $0) }
        NSGraphicsContext.restoreGraphicsState()

        // Selection handles (view space, crisp at any zoom) — only in Select
        // mode, so back-to-back drawing isn't cluttered by the last shape's frame.
        if doc.tool == .select, let sel = doc.selectedObject, sel.isVisible {
            drawSelection(sel)
        }

        // Crop overlay
        if doc.tool == .crop {
            drawCropOverlay(doc: doc, canvasRect: canvasRect)
        }
    }

    private func drawSelection(_ obj: CanvasObject) {
        let accent = NSColor.controlAccentColor
        if obj.kind == .line || obj.kind == .arrow {
            for p in [obj.start, obj.end] { drawHandleDot(at: toView(p), accent: accent) }
        } else {
            let r = toView(obj.rect)
            let outline = NSBezierPath(rect: r.insetBy(dx: -2, dy: -2))
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            accent.withAlphaComponent(0.9).setStroke()
            outline.stroke()
            for p in handlePoints(for: r) { drawHandleDot(at: p, accent: accent) }
        }
    }

    private func drawHandleDot(at p: NSPoint, accent: NSColor) {
        let r = NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
        let path = NSBezierPath(ovalIn: r)
        NSColor.white.setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func handlePoints(for r: NSRect) -> [NSPoint] {
        let xs = [r.minX, r.midX, r.maxX]
        let ys = [r.minY, r.midY, r.maxY]
        // order matches Handle.corner: tl tm tr ml mr bl bm br
        return [NSPoint(x: xs[0], y: ys[0]), NSPoint(x: xs[1], y: ys[0]), NSPoint(x: xs[2], y: ys[0]),
                NSPoint(x: xs[0], y: ys[1]), NSPoint(x: xs[2], y: ys[1]),
                NSPoint(x: xs[0], y: ys[2]), NSPoint(x: xs[1], y: ys[2]), NSPoint(x: xs[2], y: ys[2])]
    }

    private func drawCropOverlay(doc: CanvasDocument, canvasRect: NSRect) {
        guard let crop = doc.cropRect else {
            // No rect yet: dim the whole canvas lightly as a "crop armed" hint
            NSColor.black.withAlphaComponent(0.25).setFill()
            canvasRect.fill()
            return
        }
        let cropView = toView(crop)
        let dim = NSBezierPath(rect: canvasRect)
        dim.append(NSBezierPath(rect: cropView).reversed)
        NSColor.black.withAlphaComponent(0.55).setFill()
        dim.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropView)
        border.lineWidth = 2
        border.stroke()

        // Rule-of-thirds
        NSColor.white.withAlphaComponent(0.28).setStroke()
        for f in [1.0 / 3.0, 2.0 / 3.0] {
            let v = NSBezierPath()
            v.move(to: NSPoint(x: cropView.minX + cropView.width * f, y: cropView.minY))
            v.line(to: NSPoint(x: cropView.minX + cropView.width * f, y: cropView.maxY))
            v.lineWidth = 1
            v.stroke()
            let hpath = NSBezierPath()
            hpath.move(to: NSPoint(x: cropView.minX, y: cropView.minY + cropView.height * f))
            hpath.line(to: NSPoint(x: cropView.maxX, y: cropView.minY + cropView.height * f))
            hpath.lineWidth = 1
            hpath.stroke()
        }

        for p in handlePoints(for: cropView) {
            let r = NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Dimension chip
        let label = "\(Int(crop.width.rounded())) × \(Int(crop.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attrs)
        let chip = NSRect(x: cropView.maxX - textSize.width - 16,
                          y: min(cropView.maxY + 8, bounds.maxY - textSize.height - 14),
                          width: textSize.width + 16, height: textSize.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6).fill()
        label.draw(at: NSPoint(x: chip.minX + 8, y: chip.minY + 3), withAttributes: attrs)
    }

    // MARK: Hit testing

    private func handleHit(at viewPoint: NSPoint, for obj: CanvasObject) -> Handle? {
        let tolerance: CGFloat = 7
        if obj.kind == .line || obj.kind == .arrow {
            if toView(obj.start).distance(to: viewPoint) <= tolerance { return .start }
            if toView(obj.end).distance(to: viewPoint) <= tolerance { return .end }
            return nil
        }
        let points = handlePoints(for: toView(obj.rect))
        for (i, p) in points.enumerated() where p.distance(to: viewPoint) <= tolerance {
            return .corner(i)
        }
        return nil
    }

    private func cropHandleHit(at viewPoint: NSPoint, crop: CGRect) -> Handle? {
        let points = handlePoints(for: toView(crop))
        for (i, p) in points.enumerated() where p.distance(to: viewPoint) <= 8 {
            return .corner(i)
        }
        return nil
    }

    private func objectHit(at imagePoint: CGPoint, viewPoint: NSPoint, in doc: CanvasDocument) -> CanvasObject? {
        for obj in doc.objects.reversed() where obj.isVisible {
            switch obj.kind {
            case .pen:
                if let pts = obj.points, pts.count > 1 {
                    let tolerance = max(8, obj.width * scale)
                    for i in 0..<(pts.count - 1)
                    where imagePoint.distanceToSegment(pts[i], pts[i + 1]) * scale <= tolerance {
                        return obj
                    }
                }
            case .line, .arrow:
                let dist = imagePoint.distanceToSegment(obj.start, obj.end) * scale
                if dist <= max(8, obj.width * scale) { return obj }
            case .rect, .ellipse:
                let r = obj.rect
                let near = max(8 / scale, obj.width)
                let outer = r.insetBy(dx: -near, dy: -near)
                let inner = r.insetBy(dx: near, dy: near)
                if outer.contains(imagePoint) && !(inner.width > 0 && inner.height > 0 && inner.contains(imagePoint)) {
                    return obj
                }
            case .image:
                if obj.rect.contains(imagePoint) { return obj }
            }
        }
        return nil
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let doc = document, doc.canvasSize != nil else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pt = toImage(viewPoint)

        switch doc.tool {
        case .crop:
            if let crop = doc.cropRect {
                if let handle = cropHandleHit(at: viewPoint, crop: crop) {
                    drag = .cropResize(handle)
                    return
                }
                if crop.contains(pt) {
                    drag = .cropMove(last: pt)
                    return
                }
            }
            doc.cropRect = CGRect(origin: clampToCanvas(pt), size: .zero)
            drag = .cropNew(anchor: clampToCanvas(pt))

        case .pen, .line, .rect, .ellipse, .arrow:
            let kind: CanvasObject.Kind = switch doc.tool {
            case .pen: .pen
            case .line: .line
            case .rect: .rect
            case .ellipse: .ellipse
            default: .arrow
            }
            doc.pushUndo()
            var obj = doc.addShape(kind: kind, start: pt, end: pt)
            // The chosen stroke width is what the user SEES at the current zoom;
            // store it in image pixels so it stays proportional on the real image.
            obj.width = doc.strokeWidth / max(scale, 0.125)
            doc.updateObject(obj)
            doc.selectedID = obj.id
            drag = .creating(obj.id)

        case .select:
            if let sel = doc.selectedObject, let handle = handleHit(at: viewPoint, for: sel) {
                drag = .resizing(sel.id, handle, pushed: false)
                return
            }
            if let hit = objectHit(at: pt, viewPoint: viewPoint, in: doc) {
                doc.selectedID = hit.id
                drag = .moving(hit.id, last: pt, pushed: false)
            } else {
                doc.selectedID = nil
                drag = .none
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = document else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        var pt = toImage(viewPoint)
        let shift = event.modifierFlags.contains(.shift)

        switch drag {
        case .none:
            return

        case .creating(let id):
            guard var obj = doc.objects.first(where: { $0.id == id }) else { return }
            if obj.kind == .pen {
                // Coalesce samples closer than ~1 screen px — keeps the stored
                // path small and avoids re-publishing the model for micro-moves.
                if let last = obj.points?.last, last.distance(to: pt) * scale < 1.0 { return }
                obj.points?.append(pt)
                obj.end = pt
            } else {
                if shift { pt = constrain(pt, from: obj.start, kind: obj.kind) }
                obj.end = pt
            }
            doc.updateObject(obj)

        case .moving(let id, let last, let pushed):
            guard var obj = doc.objects.first(where: { $0.id == id }) else { return }
            if !pushed { doc.pushUndo() }
            obj.move(by: CGPoint(x: pt.x - last.x, y: pt.y - last.y))
            doc.updateObject(obj)
            drag = .moving(id, last: pt, pushed: true)

        case .resizing(let id, let handle, let pushed):
            guard var obj = doc.objects.first(where: { $0.id == id }) else { return }
            if !pushed { doc.pushUndo() }
            apply(handle: handle, point: pt, to: &obj)
            doc.updateObject(obj)
            drag = .resizing(id, handle, pushed: true)

        case .cropNew(let anchor):
            let p = clampToCanvas(pt)
            doc.cropRect = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y),
                                  width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))

        case .cropMove(let last):
            guard var crop = doc.cropRect, let size = doc.canvasSize else { return }
            crop.origin.x += pt.x - last.x
            crop.origin.y += pt.y - last.y
            crop.origin.x = max(0, min(crop.origin.x, size.width - crop.width))
            crop.origin.y = max(0, min(crop.origin.y, size.height - crop.height))
            doc.cropRect = crop
            drag = .cropMove(last: pt)

        case .cropResize(let handle):
            guard var crop = doc.cropRect else { return }
            resizeRect(&crop, handle: handle, point: clampToCanvas(pt))
            doc.cropRect = crop
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document else { drag = .none; return }
        switch drag {
        case .creating(let id):
            if let obj = doc.objects.first(where: { $0.id == id }) {
                // "Was this just a click?" — a pen LOOP ends near its start, so
                // judge pens by their bounding box, never by start→end distance.
                let tooSmall = obj.kind == .pen
                    ? max(obj.rect.width, obj.rect.height) * scale < 3
                    : obj.start.distance(to: obj.end) * scale < 3
                if tooSmall {
                    doc.objects.removeAll { $0.id == id }
                    doc.selectedID = nil
                    doc.discardLastUndo()
                }
            }
        case .cropNew:
            if let crop = doc.cropRect, crop.width < 3 || crop.height < 3 {
                doc.cropRect = nil
            }
        default:
            break
        }
        drag = .none
        needsDisplay = true
    }

    private func constrain(_ p: CGPoint, from anchor: CGPoint, kind: CanvasObject.Kind) -> CGPoint {
        switch kind {
        case .line, .arrow:
            // Snap to 45° increments
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            let angle = atan2(dy, dx)
            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
            let len = sqrt(dx * dx + dy * dy)
            return CGPoint(x: anchor.x + cos(snapped) * len, y: anchor.y + sin(snapped) * len)
        default:
            // Square / circle
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: anchor.x + (dx < 0 ? -side : side), y: anchor.y + (dy < 0 ? -side : side))
        }
    }

    private func apply(handle: Handle, point: CGPoint, to obj: inout CanvasObject) {
        switch handle {
        case .start: obj.start = point
        case .end: obj.end = point
        case .corner(let i):
            let old = obj.rect
            var r = old
            resizeRect(&r, handle: .corner(i), point: point)
            obj.start = r.origin
            obj.end = CGPoint(x: r.maxX, y: r.maxY)
            if obj.kind == .pen { obj.mapPoints(from: old, to: r) }
        }
    }

    private func resizeRect(_ r: inout CGRect, handle: Handle, point: CGPoint) {
        guard case .corner(let i) = handle else { return }
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch i {
        case 0: minX = point.x; minY = point.y
        case 1: minY = point.y
        case 2: maxX = point.x; minY = point.y
        case 3: minX = point.x
        case 4: maxX = point.x
        case 5: minX = point.x; maxY = point.y
        case 6: maxY = point.y
        case 7: maxX = point.x; maxY = point.y
        default: break
        }
        r = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                   width: abs(maxX - minX), height: abs(maxY - minY))
    }

    private func clampToCanvas(_ p: CGPoint) -> CGPoint {
        guard let size = document?.canvasSize else { return p }
        return CGPoint(x: max(0, min(p.x, size.width)), y: max(0, min(p.y, size.height)))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// Returns true when the key was consumed. Shared by keyDown and the local
    /// monitor below — SwiftUI's hosting view swallows bare-letter keys before
    /// they reach an NSViewRepresentable, so the monitor is the reliable path.
    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let doc = document, doc.canvasSize != nil else { return false }
        let noMods = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        guard noMods else { return false }

        switch event.keyCode {
        case 51, 117: // delete / forward delete
            if doc.selectedID != nil { doc.removeSelected(); return true }
            return false
        case 53: // esc
            if doc.tool == .crop { doc.cancelCrop() } else if doc.selectedID != nil { doc.selectedID = nil } else { return false }
            return true
        case 36, 76: // return / enter
            if doc.tool == .crop, doc.cropRect != nil { doc.applyCrop(); return true }
            return false
        default:
            break
        }

        // Match tool keys by PHYSICAL key position (kVK_ANSI_*), not by character:
        // on the Thai layout charactersIgnoringModifiers is the Thai glyph
        // ("อ" for the V key), which silenced SheepTerm's shortcuts until 2.3 (9).
        switch event.keyCode {
        case 9:  doc.tool = .select;  return true   // V
        case 35: doc.tool = .pen;     return true   // P
        case 37: doc.tool = .line;    return true   // L
        case 15: doc.tool = .rect;    return true   // R
        case 31: doc.tool = .ellipse; return true   // O
        case 0:  doc.tool = .arrow;   return true   // A
        case 8:  doc.tool = .crop;    return true   // C
        case 30: doc.bringToFront();  return true   // ]
        case 33: doc.sendToBack();    return true   // [
        default: return false
        }
    }

    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Take key focus immediately so shortcuts work before the first click.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let win = self.window, event.window === win, win.isKeyWindow else {
                        return event
                    }
                    return self.handleKey(event) ? nil : event
                }
            }
        } else if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: Context menu — restyle a shape right where it is

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let doc = document, doc.canvasSize != nil, doc.tool != .crop else { return nil }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pt = toImage(viewPoint)
        guard let hit = objectHit(at: pt, viewPoint: viewPoint, in: doc) else { return nil }
        doc.selectedID = hit.id
        needsDisplay = true

        let menu = NSMenu()
        if !hit.isImage {
            let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            let colorMenu = NSMenu()
            for (name, color) in ToolbarRow.palette {
                let item = NSMenuItem(title: name, action: #selector(applyColorItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = color
                item.image = Self.swatch(color)
                colorMenu.addItem(item)
            }
            menu.addItem(colorItem)
            menu.setSubmenu(colorMenu, for: colorItem)

            let widthItem = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
            let widthMenu = NSMenu()
            for (name, width) in ToolbarRow.widths {
                let item = NSMenuItem(title: name, action: #selector(applyWidthItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = width
                widthMenu.addItem(item)
            }
            menu.addItem(widthItem)
            menu.setSubmenu(widthMenu, for: widthItem)
            menu.addItem(.separator())
        }
        menu.addItem(contextItem("Bring to Front", #selector(bringToFrontItem)))
        menu.addItem(contextItem("Send to Back", #selector(sendToBackItem)))
        menu.addItem(.separator())
        menu.addItem(contextItem("Duplicate", #selector(duplicateItem)))
        if hit.isImage {
            menu.addItem(contextItem("Remove Background", #selector(removeBackgroundItem)))
        }
        menu.addItem(.separator())
        menu.addItem(contextItem("Delete", #selector(deleteItem)))
        return menu
    }

    private func contextItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: 12, height: 12)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        NSBezierPath(ovalIn: rect).stroke()
        image.unlockFocus()
        return image
    }

    @objc private func applyColorItem(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? NSColor, let doc = document else { return }
        doc.strokeColor = color
        doc.setColor(color)
    }

    @objc private func applyWidthItem(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Double, let doc = document else { return }
        doc.strokeWidth = width
        doc.setWidth(width)
    }

    @objc private func bringToFrontItem() { document?.bringToFront() }
    @objc private func sendToBackItem() { document?.sendToBack() }
    @objc private func duplicateItem() { document?.duplicateSelection() }
    @objc private func removeBackgroundItem() { document?.removeBackgroundFromSelection() }
    @objc private func deleteItem() { document?.removeSelected() }

    override func resetCursorRects() {
        guard let doc = document else { return }
        let cursor: NSCursor = doc.tool == .select ? .arrow : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}

// MARK: - SwiftUI wrapper

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var document: CanvasDocument

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.document = document
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.document = document
        nsView.needsDisplay = true
    }
}
