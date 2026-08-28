import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let sheepArtProject = UTType(exportedAs: "com.bestchaan.sheepart.project")
}

extension CanvasDocument {
    // MARK: Save PNG (⌘S) — flattened, like every export path

    func savePNG() {
        guard let img = renderFlattened(), let png = pngData(from: img) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "SheepArt.png"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
                self?.flash("Saved PNG")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: Save Project (⇧⌘S) — .sheepart keeps every layer editable

    func saveProject() {
        if let url = projectURL {
            writeProject(to: url)
            return
        }
        saveProjectAs()
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sheepArtProject]
        panel.nameFieldStringValue = "Untitled.sheepart"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writeProject(to: url)
        }
    }

    private func writeProject(to url: URL) {
        guard let size = canvasSize else { return }
        let file = ProjectFile(canvasWidth: size.width, canvasHeight: size.height, objects: objects)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: url)
            projectURL = url
            isDirty = false
            flash("Saved project")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Open (⌘O) — .sheepart projects, or images (base canvas / new layer)

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sheepArtProject, .png, .jpeg, .tiff, .heic, .gif, .bmp, .webP]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url: url)
        }
    }

    func open(url: URL) {
        if url.pathExtension.lowercased() == "sheepart" {
            do {
                let data = try Data(contentsOf: url)
                let file = try JSONDecoder().decode(ProjectFile.self, from: data)
                load(project: file, from: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        } else if let img = NSImage(contentsOf: url) {
            addImage(img, named: url.deletingPathExtension().lastPathComponent)
        }
    }
}
