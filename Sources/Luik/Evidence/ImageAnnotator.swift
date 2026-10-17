import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// One mark on a screenshot, in image pixel coordinates (origin top-left).
struct ImageAnnotation: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case arrow, rectangle, ellipse, text, blur, redact, highlight

        var id: String { rawValue }

        var label: String {
            switch self {
            case .arrow: return "Arrow"
            case .rectangle: return "Box"
            case .ellipse: return "Circle"
            case .text: return "Text"
            case .blur: return "Blur"
            case .redact: return "Redact"
            case .highlight: return "Highlight"
            }
        }

        var icon: String {
            switch self {
            case .arrow: return "arrow.up.right"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .text: return "textformat"
            case .blur: return "drop.halffull"
            case .redact: return "rectangle.fill"
            case .highlight: return "highlighter"
            }
        }

        var help: String {
            switch self {
            case .arrow: return "Drag from the tail to the head"
            case .rectangle: return "Drag a box around something"
            case .ellipse: return "Drag an ellipse around something"
            case .text: return "Click where the label goes, then type"
            case .blur: return "Drag over what must not be readable — pixelated in the saved image"
            case .redact: return "Drag over what must disappear — solid black in the saved image"
            case .highlight: return "Drag a translucent marker over text"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var text: String = ""
    var colorIndex: Int = 0
    var lineWidth: CGFloat = 4

    init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint, text: String = "", colorIndex: Int = 0, lineWidth: CGFloat = 4) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.colorIndex = colorIndex
        self.lineWidth = lineWidth
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    func moved(by delta: CGSize) -> ImageAnnotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
        copy.end = CGPoint(x: end.x + delta.width, y: end.y + delta.height)
        return copy
    }

    /// Hit area for selection, in image pixels.
    func hitRect(fontSize: CGFloat) -> CGRect {
        switch kind {
        case .text:
            let size = ImageAnnotationRenderer.textSize(text, fontSize: fontSize)
            return CGRect(x: start.x, y: start.y, width: size.width + 16, height: size.height + 10)
        case .arrow:
            return rect.insetBy(dx: -12, dy: -12)
        default:
            return rect.insetBy(dx: -6, dy: -6)
        }
    }
}

/// Colours for marks: red first (what you point at), then the rest.
enum AnnotationPalette {
    static let colors: [NSColor] = [
        NSColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1),
        NSColor(red: 1.00, green: 0.62, blue: 0.10, alpha: 1),
        NSColor(red: 1.00, green: 0.90, blue: 0.20, alpha: 1),
        NSColor(red: 0.25, green: 0.80, blue: 0.35, alpha: 1),
        NSColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1),
        NSColor.white,
        NSColor.black,
    ]

    static func color(_ index: Int) -> NSColor {
        colors[min(max(index, 0), colors.count - 1)]
    }
}

/// Draws the marks onto a CGContext (used for the saved image) and makes the pixelated copy.
enum ImageAnnotationRenderer {
    /// A coarse copy of the image: every blur mark shows the matching part of it.
    static func pixelated(_ image: CGImage, block: Int) -> CGImage? {
        let block = max(block, 2)
        let smallWidth = max(image.width / block, 1)
        let smallHeight = max(image.height / block, 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let shrunk = small.makeImage(),
              let big = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        big.interpolationQuality = .none
        big.draw(shrunk, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return big.makeImage()
    }

    static func blockSize(for image: CGImage) -> Int {
        max(8, min(image.width, image.height) / 90)
    }

    static func font(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let attributed = NSAttributedString(string: text.isEmpty ? "Text" : text, attributes: [.font: font(fontSize)])
        return attributed.size()
    }

    /// The image with every mark burnt in, as PNG data at the original pixel size.
    static func render(_ image: CGImage, annotations: [ImageAnnotation], fontSize: CGFloat) -> Data? {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixelated = annotations.contains { $0.kind == .blur } ? pixelated(image, block: blockSize(for: image)) : nil

        // Image coordinates have their origin top-left; flip once for the marks.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for annotation in annotations {
            draw(annotation, in: context, pixelated: pixelated, imageHeight: CGFloat(height), fontSize: fontSize)
        }
        guard let output = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(_ annotation: ImageAnnotation, in context: CGContext, pixelated: CGImage?, imageHeight: CGFloat, fontSize: CGFloat) {
        let color = AnnotationPalette.color(annotation.colorIndex).cgColor
        let rect = annotation.rect
        context.saveGState()
        defer { context.restoreGState() }
        switch annotation.kind {
        case .blur:
            guard let pixelated, rect.width > 0, rect.height > 0 else { return }
            context.clip(to: rect)
            // Back to the image's own orientation for drawing the pixelated copy.
            context.translateBy(x: 0, y: imageHeight)
            context.scaleBy(x: 1, y: -1)
            context.draw(pixelated, in: CGRect(x: 0, y: 0, width: CGFloat(pixelated.width), height: CGFloat(pixelated.height)))
        case .redact:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(rect)
        case .highlight:
            context.setFillColor(AnnotationPalette.color(annotation.colorIndex).withAlphaComponent(0.35).cgColor)
            context.fill(rect)
        case .rectangle:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.stroke(rect.insetBy(dx: annotation.lineWidth / 2, dy: annotation.lineWidth / 2))
        case .ellipse:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.strokeEllipse(in: rect.insetBy(dx: annotation.lineWidth / 2, dy: annotation.lineWidth / 2))
        case .arrow:
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round)
            let path = arrowPath(from: annotation.start, to: annotation.end, lineWidth: annotation.lineWidth)
            context.addPath(path.line)
            context.strokePath()
            context.addPath(path.head)
            context.fillPath()
        case .text:
            let attributed = NSAttributedString(string: annotation.text.isEmpty ? "Text" : annotation.text,
                                                attributes: [.font: font(fontSize), .foregroundColor: NSColor.white])
            let size = attributed.size()
            let box = CGRect(x: annotation.start.x, y: annotation.start.y, width: size.width + 16, height: size.height + 10)
            context.setFillColor(AnnotationPalette.color(annotation.colorIndex).withAlphaComponent(0.92).cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.fillPath()
            // Text wants an unflipped context with a flipped NSGraphicsContext.
            context.translateBy(x: 0, y: imageHeight)
            context.scaleBy(x: 1, y: -1)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            let origin = CGPoint(x: box.minX + 8, y: imageHeight - box.maxY + 5)
            attributed.draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Line plus a filled triangular head at `to`.
    static func arrowPath(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (line: CGPath, head: CGPath) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / length, uy = dy / length
        let headLength = max(lineWidth * 4, 14)
        let headWidth = max(lineWidth * 2.2, 8)
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        let line = CGMutablePath()
        line.move(to: from)
        line.addLine(to: base)
        let head = CGMutablePath()
        head.move(to: to)
        head.addLine(to: CGPoint(x: base.x + -uy * headWidth, y: base.y + ux * headWidth))
        head.addLine(to: CGPoint(x: base.x - -uy * headWidth, y: base.y - ux * headWidth))
        head.closeSubpath()
        return (line, head)
    }
}

/// Image files referenced from a finding's evidence text (Markdown image links or bare paths).
enum EvidenceImages {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"]

    static func paths(in text: String) -> [String] {
        var found: [String] = []
        let pattern = #"!\[[^\]]*\]\(([^)]+)\)|((?:/|~/)[^\s"']+\.(?:png|jpe?g|gif|tiff|heic|webp))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            for group in 1...2 {
                guard let r = Range(match.range(at: group), in: text) else { continue }
                var path = String(text[r]).trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
                path = path.removingPercentEncoding ?? path
                path = (path as NSString).expandingTildeInPath
                if extensions.contains((path as NSString).pathExtension.lowercased()), !found.contains(path) {
                    found.append(path)
                }
            }
        }
        return found
    }
}
