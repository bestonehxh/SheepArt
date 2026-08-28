import AppKit
import Combine
import SwiftUI

/// One window's document: a fixed-size canvas holding a z-ordered list of
/// objects (image layers + shapes). Coordinates live in IMAGE SPACE from day
/// one — origin top-left, +y down — so zoom and crop can never corrupt them.
final class CanvasDocument: ObservableObject {
    @Published var objects: [CanvasObject] = []
    @Published var canvasSize: CGSize? = nil
    @Published var selectedID: UUID? = nil
    @Published var tool: Tool = .select {
        didSet { if oldValue == .crop && tool != .crop { cropRect = nil } }
    }
    @Published var strokeColor: NSColor = .systemRed
    @Published var strokeWidth: Double = 3.5
    @Published var cropRect: CGRect? = nil
    @Published var displayScale: CGFloat = 1
    @Published var showLayers: Bool = false
    @Published var isDirty: Bool = false
    @Published var statusFlash: String? = nil

    /// Where "Save Project" last wrote, so ⇧⌘S can overwrite in place.
    var projectURL: URL? = nil

    private var imageCache: [UUID: NSImage] = [:]
    private var imageCounter = 0
    private var flashTask: Task<Void, Never>? = nil

    var selectedObject: CanvasObject? {
        guard let id = selectedID else { return nil }
        return objects.first { $0.id == id }
    }

    var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return objects.firstIndex { $0.id == id }
    }

    // MARK: Undo (whole-state snapshots; the object graph is small)

    struct Snapshot {
        var objects: [CanvasObject]
        var canvasSize: CGSize?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func pushUndo() {
        undoStack.append(Snapshot(objects: objects, canvasSize: canvasSize))
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
    }

    /// Drops the most recent snapshot — for gestures that turned out to be no-ops
    /// (e.g. a click that created a zero-size shape and was rolled back by hand).
    func discardLastUndo() {
        _ = undoStack.popLast()
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(Snapshot(objects: objects, canvasSize: canvasSize))
        restore(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(Snapshot(objects: objects, canvasSize: canvasSize))
        restore(snap)
    }

    private func restore(_ snap: Snapshot) {
        objects = snap.objects
        canvasSize = snap.canvasSize
        if let id = selectedID, !objects.contains(where: { $0.id == id }) { selectedID = nil }
        cropRect = nil
        isDirty = true
        // A snapshot may carry different imageData under the same id (e.g. undo
        // of Remove Background) — a stale cache entry would keep rendering the
        // new pixels, so drop everything and let it re-decode lazily.
        imageCache.removeAll()
    }

    // MARK: Restyle (toolbar color/width with a selection, and the context menu)

    func setColor(_ color: NSColor, forSelectionOr id: UUID? = nil) {
        guard let i = index(of: id), !objects[i].isImage else { return }
        pushUndo()
        objects[i].color = CodableColor(color)
    }

    func setWidth(_ width: Double, forSelectionOr id: UUID? = nil) {
        guard let i = index(of: id), !objects[i].isImage else { return }
        pushUndo()
        objects[i].width = width
    }

    private func index(of id: UUID?) -> Int? {
        let target = id ?? selectedID
        guard let target else { return nil }
        return objects.firstIndex { $0.id == target }
    }

    // MARK: Object access

    func image(for obj: CanvasObject) -> NSImage? {
        guard obj.isImage else { return nil }
        if let cached = imageCache[obj.id] { return cached }
        guard let data = obj.imageData, let img = NSImage(data: data) else { return nil }
        imageCache[obj.id] = img
        return img
    }

    func updateObject(_ obj: CanvasObject) {
        guard let i = objects.firstIndex(where: { $0.id == obj.id }) else { return }
        objects[i] = obj
    }

    func replaceImageData(id: UUID, data: Data) {
        guard let i = objects.firstIndex(where: { $0.id == id }), objects[i].isImage else { return }
        pushUndo()
        objects[i].imageData = data
        imageCache.removeValue(forKey: id)
    }

    func toggleVisibility(id: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        objects[i].isVisible.toggle()
    }

    /// Reorders layers from the panel, which lists TOPMOST FIRST.
    func moveLayers(fromTopFirstOffsets source: IndexSet, toTopFirstOffset destination: Int) {
        pushUndo()
        var topFirst = Array(objects.reversed())
        topFirst.move(fromOffsets: source, toOffset: destination)
        objects = topFirst.reversed()
    }

    func removeSelected() {
        guard let i = selectedIndex else { return }
        pushUndo()
        imageCache.removeValue(forKey: objects[i].id)
        objects.remove(at: i)
        selectedID = nil
    }

    // MARK: Adding content

    /// Paint-style blank page: a white canvas with no base image.
    func newBlankCanvas(size: CGSize) {
        pushUndo()
        objects = []
        canvasSize = size
        selectedID = nil
        cropRect = nil
        imageCache.removeAll()
        imageCounter = 0
        tool = .pen
        flash("New \(Int(size.width)) × \(Int(size.height)) canvas")
    }

    /// First image defines the canvas; later images stack as new layers.
    func addImage(_ img: NSImage, named: String? = nil) {
        guard let size = pixelSize(of: img), size.width > 0, size.height > 0 else { return }
        pushUndo()
        imageCounter += 1
        let name = named ?? "Image \(imageCounter)"
        var obj = CanvasObject(kind: .image, start: .zero, end: CGPoint(x: size.width, y: size.height))
        obj.imageData = pngData(from: img)
        obj.name = name
        if let canvas = canvasSize {
            // Stack on top, scaled down to fit if it would overflow, offset a bit.
            var w = size.width, h = size.height
            let fit = min(1, min(canvas.width * 0.9 / w, canvas.height * 0.9 / h))
            w *= fit; h *= fit
            let origin = CGPoint(x: (canvas.width - w) / 2 + 16, y: (canvas.height - h) / 2 + 16)
            obj.start = origin
            obj.end = CGPoint(x: origin.x + w, y: origin.y + h)
        } else {
            canvasSize = size
        }
        imageCache[obj.id] = img
        objects.append(obj)
        selectedID = canvasSize == nil || objects.count == 1 ? nil : obj.id
        if tool == .crop { tool = .select }
    }

    func addShape(kind: CanvasObject.Kind, start: CGPoint, end: CGPoint) -> CanvasObject {
        var obj = CanvasObject(kind: kind, start: start, end: end)
        obj.color = CodableColor(strokeColor)
        obj.width = strokeWidth
        obj.name = defaultName(for: kind)
        if kind == .pen { obj.points = [start] }
        objects.append(obj)
        return obj
    }

    private func defaultName(for kind: CanvasObject.Kind) -> String {
        let base: String = switch kind {
        case .pen: "Pen"
        case .line: "Line"
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .image: "Image"
        }
        let n = objects.count(where: { $0.kind == kind }) + 1
        return "\(base) \(n)"
    }

    // MARK: Z-order

    func bringToFront() {
        guard let i = selectedIndex, i < objects.count - 1 else { return }
        pushUndo()
        let obj = objects.remove(at: i)
        objects.append(obj)
    }

    func sendToBack() {
        guard let i = selectedIndex, i > 0 else { return }
        pushUndo()
        let obj = objects.remove(at: i)
        objects.insert(obj, at: 0)
    }

    // MARK: Crop (non-destructive to objects: everything just shifts origin)

    func applyCrop() {
        guard let rect = cropRect, rect.width > 2, rect.height > 2 else { return }
        pushUndo()
        let delta = CGPoint(x: -rect.origin.x, y: -rect.origin.y)
        for i in objects.indices { objects[i].move(by: delta) }
        canvasSize = rect.size
        cropRect = nil
        tool = .select
    }

    func cancelCrop() {
        cropRect = nil
        tool = .select
    }

    // MARK: Flatten (shared by ⌘C, ⌘S and drag-out)

    func renderFlattened() -> NSImage? {
        guard let size = canvasSize else { return nil }
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: w * 4, bitsPerPixel: 32) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        // Flip so image space (+y down) lands correctly in the bitmap.
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: CGFloat(h))
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
        ObjectRenderer.draw(objects) { [weak self] in self?.image(for: $0) }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    /// Renders one object alone (for copying a shape to other apps as PNG).
    func renderObject(_ obj: CanvasObject) -> NSImage? {
        let pad = obj.width * 4 + 8
        let r = obj.rect.insetBy(dx: -pad, dy: -pad)
        let w = Int(r.width.rounded()), h = Int(r.height.rounded())
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: w * 4, bitsPerPixel: 32) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: CGFloat(h))
        transform.scaleX(by: 1, yBy: -1)
        transform.translateX(by: -r.origin.x, yBy: -r.origin.y)
        transform.concat()
        var copy = obj
        copy.isVisible = true
        ObjectRenderer.draw([copy]) { [weak self] in self?.image(for: $0) }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: r.size)
        out.addRepresentation(rep)
        return out
    }

    // MARK: Project load

    func load(project: ProjectFile, from url: URL?) {
        pushUndo()
        objects = project.objects
        canvasSize = CGSize(width: project.canvasWidth, height: project.canvasHeight)
        selectedID = nil
        cropRect = nil
        imageCache.removeAll()
        imageCounter = objects.count(where: { $0.isImage })
        projectURL = url
        isDirty = false
    }

    func flash(_ message: String) {
        statusFlash = message
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { self?.statusFlash = nil }
        }
    }

    // MARK: Image helpers

    func pixelSize(of img: NSImage) -> CGSize? {
        if let rep = img.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return img.size.width > 0 ? img.size : nil
    }

    func pngData(from img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
