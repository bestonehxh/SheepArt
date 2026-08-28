import SwiftUI

@main
struct SheepArtApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1160, height: 780)
        .commands { AppCommands() }
    }
}

struct AppCommands: Commands {
    @FocusedObject private var doc: CanvasDocument?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("New Canvas") {
                Button("1440 × 900") { doc?.newBlankCanvas(size: CGSize(width: 1440, height: 900)) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("1280 × 720") { doc?.newBlankCanvas(size: CGSize(width: 1280, height: 720)) }
                Button("1920 × 1080") { doc?.newBlankCanvas(size: CGSize(width: 1920, height: 1080)) }
                Button("2048 × 2048") { doc?.newBlankCanvas(size: CGSize(width: 2048, height: 2048)) }
            }
            .disabled(doc == nil)
            Button("Open…") { doc?.openFile() }
                .keyboardShortcut("o")
                .disabled(doc == nil)
            Button("Capture Screen…") { doc?.captureScreen() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(doc == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save PNG…") { doc?.savePNG() }
                .keyboardShortcut("s")
                .disabled(doc?.canvasSize == nil)
            Button("Save Project…") { doc?.saveProject() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(doc?.canvasSize == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { doc?.undo() }
                .keyboardShortcut("z")
                .disabled(doc == nil)
            Button("Redo") { doc?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(doc == nil)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { doc?.cutToClipboard() }
                .keyboardShortcut("x")
                .disabled(doc?.selectedObject == nil)
            Button("Copy") { doc?.copyToClipboard() }
                .keyboardShortcut("c")
                .disabled(doc?.canvasSize == nil)
            Button("Paste") { doc?.pasteFromClipboard() }
                .keyboardShortcut("v")
                .disabled(doc == nil)
            Button("Duplicate") { doc?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(doc?.selectedObject == nil)
            Button("Delete") { doc?.removeSelected() }
                .disabled(doc?.selectedObject == nil)
        }

        CommandMenu("Object") {
            Button("Bring to Front") { doc?.bringToFront() }
                .keyboardShortcut("]")
                .disabled(doc?.selectedObject == nil)
            Button("Send to Back") { doc?.sendToBack() }
                .keyboardShortcut("[")
                .disabled(doc?.selectedObject == nil)
            Divider()
            Button("Remove Background") { doc?.removeBackgroundFromSelection() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!(doc?.selectedObject?.isImage ?? false))
        }

        CommandGroup(after: .sidebar) {
            Button("Show Layers") { doc?.showLayers.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(doc?.canvasSize == nil)
        }
    }
}
