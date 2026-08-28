import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// SheepArt's own shape/layer payload — travels next to a PNG so other
    /// apps still get a picture while SheepArt gets the editable object back.
    static let sheepArtObject = NSPasteboard.PasteboardType("Bestchaan.SheepArt.object")
}

extension CanvasDocument {
    // MARK: Paste (works even before any document exists — "New from Clipboard")

    func pasteFromClipboard() {
        let pb = NSPasteboard.general

        // 1. Our own object type wins: paste an editable shape/layer, nudged so it's visible.
        if canvasSize != nil,
           let data = pb.data(forType: .sheepArtObject),
           var obj = try? JSONDecoder().decode(CanvasObject.self, from: data) {
            pushUndo()
            obj.id = UUID()
            obj.move(by: CGPoint(x: 18, y: 18))
            if !obj.name.isEmpty { obj.name += " copy" }
            objects.append(obj)
            selectedID = obj.id
            flash("Pasted \(obj.name.isEmpty ? "object" : obj.name)")
            return
        }

        // 2. An image: first one becomes the canvas, later ones stack as layers.
        if let img = NSImage(pasteboard: pb) {
            addImage(img)
            flash("Pasted image")
            return
        }

        // 3. An image FILE copied in Finder (e.g. a ⇧⌘4 screenshot saved to Desktop).
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls where NSImage(contentsOf: url) != nil {
                open(url: url)
                flash("Pasted \(url.lastPathComponent)")
                return
            }
        }
        flash("Nothing to paste — copy a screenshot first (⌃⇧⌘4)")
    }

    // MARK: In-app screen capture (no reliance on the system ⌃⇧⌘4 shortcut)

    /// Runs the system's interactive capture straight into the clipboard, then
    /// pastes the result. First use triggers the Screen Recording permission ask.
    func captureScreen() {
        let before = NSPasteboard.general.changeCount
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c"]
        NSApp.hide(nil)
        task.terminationHandler = { _ in
            Task { @MainActor [weak self] in
                NSApp.unhide(nil)
                NSApp.activate()
                guard let self else { return }
                if NSPasteboard.general.changeCount != before {
                    self.pasteFromClipboard()
                } else {
                    self.flash("Capture cancelled")
                }
            }
        }
        do {
            try task.run()
        } catch {
            NSApp.unhide(nil)
            flash("Couldn't start screen capture")
        }
    }

    // MARK: Copy (selection-aware, matching the spec)

    func copyToClipboard() {
        let pb = NSPasteboard.general
        if let sel = selectedObject {
            pb.clearContents()
            if let data = try? JSONEncoder().encode(sel) {
                pb.setData(data, forType: .sheepArtObject)
            }
            if let img = renderObject(sel), let png = pngData(from: img) {
                pb.setData(png, forType: .png)
            }
            flash("Copied \(sel.name.isEmpty ? "object" : sel.name)")
        } else if let img = renderFlattened(), let png = pngData(from: img) {
            pb.clearContents()
            pb.setData(png, forType: .png)
            if let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            flash("Copied image")
        }
    }

    func cutToClipboard() {
        guard selectedObject != nil else { return }
        copyToClipboard()
        removeSelected()
    }

    func duplicateSelection() {
        guard var obj = selectedObject else { return }
        pushUndo()
        obj.id = UUID()
        obj.move(by: CGPoint(x: 18, y: 18))
        if !obj.name.isEmpty { obj.name += " copy" }
        objects.append(obj)
        selectedID = obj.id
    }
}
