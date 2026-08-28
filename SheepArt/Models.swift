import AppKit

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable {
    case select, pen, line, rect, ellipse, arrow, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select:  "cursorarrow"
        case .pen:     "paintbrush.pointed"
        case .line:    "line.diagonal"
        case .rect:    "rectangle"
        case .ellipse: "oval"
        case .arrow:   "arrow.up.right"
        case .crop:    "crop"
        }
    }

    var label: String {
        switch self {
        case .select:  "Select"
        case .pen:     "Pen"
        case .line:    "Line"
        case .rect:    "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow:   "Arrow"
        case .crop:    "Crop"
        }
    }

    var shortcutKey: Character {
        switch self {
        case .select: "v"
        case .pen: "p"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .arrow: "a"
        case .crop: "c"
        }
    }
}

// MARK: - Color

struct CodableColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        r = c.redComponent; g = c.greenComponent; b = c.blueComponent; a = c.alphaComponent
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

// MARK: - Canvas object (shapes and image layers share one z-ordered list)

struct CanvasObject: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image, pen, line, rect, ellipse, arrow
    }

    var id: UUID = UUID()
    var kind: Kind
    // Image-space coordinates (origin top-left of the canvas, +y down).
    // line/arrow: start→end as drawn. rect/ellipse/image: any two opposite corners.
    var start: CGPoint
    var end: CGPoint
    var color: CodableColor = CodableColor(.systemRed)
    var width: Double = 3.5
    var imageData: Data? = nil
    var isVisible: Bool = true
    var name: String = ""
    /// Freehand stroke path (kind == .pen only), in image space.
    var points: [CGPoint]? = nil

    var rect: CGRect {
        if kind == .pen, let pts = points, !pts.isEmpty {
            var minX = pts[0].x, minY = pts[0].y, maxX = pts[0].x, maxY = pts[0].y
            for p in pts {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var isImage: Bool { kind == .image }

    var symbol: String {
        switch kind {
        case .image: "photo"
        case .pen: "paintbrush.pointed"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        }
    }

    mutating func move(by delta: CGPoint) {
        start.x += delta.x; start.y += delta.y
        end.x += delta.x; end.y += delta.y
        if points != nil {
            for i in points!.indices {
                points![i].x += delta.x
                points![i].y += delta.y
            }
        }
    }

    /// Scales a pen stroke's points from one bounding rect into another
    /// (used by the resize handles; other kinds derive from start/end).
    mutating func mapPoints(from old: CGRect, to new: CGRect) {
        guard var pts = points, old.width > 0.01, old.height > 0.01 else { return }
        for i in pts.indices {
            let fx = (pts[i].x - old.minX) / old.width
            let fy = (pts[i].y - old.minY) / old.height
            pts[i] = CGPoint(x: new.minX + fx * new.width, y: new.minY + fy * new.height)
        }
        points = pts
    }
}

// MARK: - Project file (.sheepart)

struct ProjectFile: Codable {
    var version: Int = 1
    var canvasWidth: Double
    var canvasHeight: Double
    var objects: [CanvasObject]
}

// MARK: - Drawing (shared by the live canvas, ⌘C flatten, and PNG export)

enum ObjectRenderer {
    /// Draws objects into the current NSGraphicsContext, which must already be
    /// set up with a FLIPPED coordinate system in image space (+y down).
    static func draw(_ objects: [CanvasObject], imageProvider: (CanvasObject) -> NSImage?) {
        for obj in objects where obj.isVisible {
            switch obj.kind {
            case .image:
                if let img = imageProvider(obj) {
                    img.draw(in: obj.rect, from: .zero, operation: .sourceOver,
                             fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                }
            case .pen:
                if let pts = obj.points, pts.count > 1 {
                    stroke(penPath(pts), obj)
                }
            case .line:
                let p = NSBezierPath()
                p.move(to: obj.start); p.line(to: obj.end)
                stroke(p, obj)
            case .rect:
                stroke(NSBezierPath(roundedRect: obj.rect, xRadius: 2, yRadius: 2), obj)
            case .ellipse:
                stroke(NSBezierPath(ovalIn: obj.rect), obj)
            case .arrow:
                drawArrow(obj)
            }
        }
    }

    /// Midpoint-smoothed freehand path: quadratic curves through segment
    /// midpoints so raw mouse samples don't render as jagged polylines.
    static func penPath(_ pts: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        if pts.count == 2 {
            path.line(to: pts[1])
            return path
        }
        var prevMid = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
        path.line(to: prevMid)
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            let cp = pts[i]  // quadratic through the sample, expressed as cubic
            let c1 = CGPoint(x: prevMid.x + 2.0 / 3.0 * (cp.x - prevMid.x),
                             y: prevMid.y + 2.0 / 3.0 * (cp.y - prevMid.y))
            let c2 = CGPoint(x: mid.x + 2.0 / 3.0 * (cp.x - mid.x),
                             y: mid.y + 2.0 / 3.0 * (cp.y - mid.y))
            path.curve(to: mid, controlPoint1: c1, controlPoint2: c2)
            prevMid = mid
        }
        path.line(to: pts[pts.count - 1])
        return path
    }

    private static func stroke(_ path: NSBezierPath, _ obj: CanvasObject) {
        obj.color.nsColor.setStroke()
        path.lineWidth = obj.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawArrow(_ obj: CanvasObject) {
        let color = obj.color.nsColor
        let dx = obj.end.x - obj.start.x, dy = obj.end.y - obj.start.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let angle = atan2(dy, dx)
        let headLen = max(10, obj.width * 3.4)
        let headWidth = headLen * 0.72
        // Shorten the shaft so it doesn't poke past the head tip.
        let shaftLen = max(len - headLen * 0.8, 0)
        let shaftEnd = CGPoint(x: obj.start.x + cos(angle) * shaftLen,
                               y: obj.start.y + sin(angle) * shaftLen)
        let shaft = NSBezierPath()
        shaft.move(to: obj.start); shaft.line(to: shaftEnd)
        shaft.lineWidth = obj.width
        shaft.lineCapStyle = .round
        color.setStroke()
        shaft.stroke()

        let tip = obj.end
        let base = CGPoint(x: tip.x - cos(angle) * headLen, y: tip.y - sin(angle) * headLen)
        let perp = CGPoint(x: -sin(angle), y: cos(angle))
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: CGPoint(x: base.x + perp.x * headWidth / 2, y: base.y + perp.y * headWidth / 2))
        head.line(to: CGPoint(x: base.x - perp.x * headWidth / 2, y: base.y - perp.y * headWidth / 2))
        head.close()
        color.setFill()
        head.fill()
    }
}

// MARK: - Geometry helpers

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    func distanceToSegment(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        if lenSq < 0.0001 { return distance(to: a) }
        var t = ((x - a.x) * abx + (y - a.y) * aby) / lenSq
        t = max(0, min(1, t))
        return distance(to: CGPoint(x: a.x + t * abx, y: a.y + t * aby))
    }
}
