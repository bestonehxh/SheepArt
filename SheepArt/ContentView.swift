import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var doc = CanvasDocument()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(doc: doc)
            Divider()
            HStack(spacing: 0) {
                ZStack {
                    CanvasRepresentable(document: doc)
                    if doc.canvasSize == nil {
                        EmptyStateView(doc: doc)
                    }
                    overlayChrome
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in doc.open(url: url) }
                    }
                    return true
                }
                if doc.showLayers && doc.canvasSize != nil {
                    Divider()
                    LayersPanel(doc: doc)
                        .frame(width: 220)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .focusedSceneObject(doc)
    }

    @ViewBuilder
    private var overlayChrome: some View {
        VStack {
            if let message = doc.statusFlash {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
                    .padding(.top, 10)
            }
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                if doc.tool == .crop && doc.canvasSize != nil {
                    CropHintBar(doc: doc)
                }
                Spacer()
            }
            .overlay(alignment: .trailing) {
                if doc.canvasSize != nil {
                    Text("\(Int((doc.displayScale * 100).rounded()))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 12)
                }
            }
            .padding(.bottom, 12)
        }
        .animation(.easeInOut(duration: 0.15), value: doc.statusFlash)
        .allowsHitTesting(doc.tool == .crop)
    }
}

// MARK: - Toolbar

struct ToolbarRow: View {
    @ObservedObject var doc: CanvasDocument

    static let palette: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow),
        ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple),
        ("Black", .black), ("White", .white),
    ]

    static let widths: [(String, Double)] = [("Thin", 2), ("Medium", 3.5), ("Thick", 6)]

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            toolCapsule
            Spacer(minLength: 0)
            rightCluster
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.bar)
    }

    private var toolCapsule: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button {
                    doc.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 28)
                        .foregroundStyle(doc.tool == tool ? Color.accentColor : Color.primary.opacity(0.75))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(doc.tool == tool ? Color(nsColor: .controlBackgroundColor) : .clear)
                                .shadow(color: .black.opacity(doc.tool == tool ? 0.18 : 0), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("\(tool.label) (\(String(tool.shortcutKey).uppercased()))")
                .keyboardShortcut(KeyEquivalent(tool.shortcutKey), modifiers: [])
                .disabled(doc.canvasSize == nil)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .opacity(doc.canvasSize == nil ? 0.4 : 1)
    }

    private var rightCluster: some View {
        HStack(spacing: 10) {
            Button {
                doc.captureScreen()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Capture Screen (⇧⌘K) — drag an area, it lands on the canvas")

            Divider().frame(height: 20)

            Menu {
                ForEach(Self.palette, id: \.0) { name, color in
                    Button {
                        doc.strokeColor = color
                        doc.setColor(color)
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color(nsColor: color))
                            Text(name)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(Color(nsColor: doc.strokeColor))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Stroke color")

            Menu {
                ForEach(Self.widths, id: \.0) { name, width in
                    Button {
                        doc.strokeWidth = width
                        doc.setWidth(width)
                    } label: {
                        if abs(doc.strokeWidth - width) < 0.01 {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                Image(systemName: "lineweight")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Stroke width")

            Divider().frame(height: 20)

            Button {
                doc.removeBackgroundFromSelection()
            } label: {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Remove Background (⇧⌘B)")
            .disabled(!(doc.selectedObject?.isImage ?? false))
            .opacity((doc.selectedObject?.isImage ?? false) ? 1 : 0.35)

            Button {
                doc.copyToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Copy (⌘C) — flattened image, or the selected object")
            .disabled(doc.canvasSize == nil)
            .opacity(doc.canvasSize == nil ? 0.35 : 1)

            Menu {
                Button("Save PNG…  (⌘S)") { doc.savePNG() }
                Button("Save Project…  (⇧⌘S)") { doc.saveProject() }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Save — PNG (flatten) or editable project")
            .disabled(doc.canvasSize == nil)
            .opacity(doc.canvasSize == nil ? 0.35 : 1)

            Button {
                doc.showLayers.toggle()
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(doc.showLayers ? Color.accentColor : Color.primary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Layers (⌥⌘L)")
            .disabled(doc.canvasSize == nil)
            .opacity(doc.canvasSize == nil ? 0.35 : 1)
        }
    }

}

// MARK: - Empty state

struct EmptyStateView: View {
    @ObservedObject var doc: CanvasDocument

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clipboard")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Paste to Start")
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 6) {
                Text("Copy a screenshot, then press")
                KeyCap("⌘V")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button {
                    doc.captureScreen()
                } label: {
                    Label("Capture Screen", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.link)
                KeyCap("⇧⌘K")
            }
            .font(.system(size: 13))
            HStack(spacing: 6) {
                Button {
                    doc.newBlankCanvas(size: CGSize(width: 1440, height: 900))
                } label: {
                    Label("New Blank Canvas", systemImage: "doc")
                }
                .buttonStyle(.link)
                KeyCap("⌥⌘N")
            }
            .font(.system(size: 13))
            HStack(spacing: 6) {
                Text("or drag an image here · ")
                Button("Open…") { doc.openFile() }
                    .buttonStyle(.link)
                KeyCap("⌘O")
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .padding(60)
        .frame(width: 520, height: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .foregroundStyle(.quaternary)
                )
        )
    }
}

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - Crop hint bar

struct CropHintBar: View {
    @ObservedObject var doc: CanvasDocument

    var body: some View {
        HStack(spacing: 10) {
            KeyCap("return")
            Text("to Crop")
            Text("·").foregroundStyle(.tertiary)
            KeyCap("esc")
            Text("to Cancel")
            if doc.cropRect != nil {
                Divider().frame(height: 16)
                Button("Crop") { doc.applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
    }
}

// MARK: - Layers panel (topmost first)

struct LayersPanel: View {
    @ObservedObject var doc: CanvasDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            List {
                ForEach(Array(doc.objects.reversed())) { obj in
                    LayerRow(doc: doc, obj: obj)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    doc.moveLayers(fromTopFirstOffsets: source, toTopFirstOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LayerRow: View {
    @ObservedObject var doc: CanvasDocument
    let obj: CanvasObject

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: obj.symbol)
                .font(.system(size: 12))
                .foregroundStyle(obj.isImage ? Color.primary : Color(nsColor: obj.color.nsColor))
                .frame(width: 18)
            Text(obj.name.isEmpty ? obj.kind.rawValue.capitalized : obj.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Button {
                doc.toggleVisibility(id: obj.id)
            } label: {
                Image(systemName: obj.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(obj.isVisible ? Color.secondary : Color.primary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(doc.selectedID == obj.id ? Color.accentColor.opacity(0.18) : .clear)
        )
        .onTapGesture { doc.selectedID = obj.id }
        .opacity(obj.isVisible ? 1 : 0.5)
    }
}
