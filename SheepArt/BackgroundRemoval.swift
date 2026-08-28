import AppKit
import Vision
import CoreImage

extension CanvasDocument {
    /// Removes the background of the selected image layer using the same
    /// Vision subject-lift machinery Photos uses. No external dependencies.
    func removeBackgroundFromSelection() {
        guard let sel = selectedObject, sel.isImage, let data = sel.imageData else {
            flash("Select an image layer first")
            return
        }
        flash("Removing background…")
        let id = sel.id
        Task.detached(priority: .userInitiated) {
            let masked = BackgroundRemover.process(data)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let masked {
                    self.replaceImageData(id: id, data: masked)
                    self.flash("Background removed")
                } else {
                    self.flash("No clear subject found")
                }
            }
        }
    }
}

enum BackgroundRemover {
    /// Runs off the main actor — Vision inference takes a moment on big images.
    nonisolated static func process(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMaskedImage(
                  ofInstances: observation.allInstances,
                  from: handler,
                  croppedToInstancesExtent: false) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        return rep.representation(using: .png, properties: [:])
    }
}
