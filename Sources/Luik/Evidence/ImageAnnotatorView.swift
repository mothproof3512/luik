import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sheet that opens a screenshot, lets you draw arrows/boxes/text and blur or redact parts of it,
/// and writes the result back — as a copy next to the original (default) or over the original.
struct ImageAnnotatorView: View {
    let url: URL
    /// Called with the file that was written (the copy or the original).
    var onSave: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme

    @State private var image: CGImage?
    @State private var pixelated: CGImage?
    @State private var annotations: [ImageAnnotation] = []
    @State private var undone: [ImageAnnotation] = []
    @State private var tool: ImageAnnotation.Kind = .arrow
    @State private var colorIndex = 0
    @State private var lineWidth: CGFloat = 4
    @State private var selectedID: UUID?
    @State private var draft: ImageAnnotation?
    @State private var dragOrigin: CGPoint?
    @State private var dragSelectionStart: ImageAnnotation?
    @State private var textDraft = ""
    @State private var editingTextID: UUID?
    @State private var replaceOriginal = false
    @State private var error: String?
    @FocusState private var textFocused: Bool

    /// Label size in image pixels, scaled with the image so it reads the same on a Retina capture.
    private var fontSize: CGFloat {
        guard let image else { return 16 }
        return max(14, CGFloat(min(image.width, image.height)) / 45)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let image {
                GeometryReader { proxy in
                    let fit = fitRect(image: image, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.35)
                        canvas(image: image, fit: fit)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                        if let editingTextID, let index = annotations.firstIndex(where: { $0.id == editingTextID }) {
                            let point = toView(annotations[index].start, fit: fit)
                            TextField("Label", text: $textDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 220)
                                .focused($textFocused)
                                .onSubmit { commitText() }
                                .onExitCommand { cancelText() }
                                .offset(x: point.x, y: point.y)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .coordinateSpace(name: "annotator")
                    .gesture(dragGesture(fit: fit))
                }
                .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error ?? "Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 1100, minHeight: 560, idealHeight: 760)
        .background(theme.backgroundColor)
        .onAppear(perform: load)
        .onChange(of: textDraft) { _, text in
            if let editingTextID, let index = annotations.firstIndex(where: { $0.id == editingTextID }) {
                annotations[index].text = text
            }
        }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(ImageAnnotation.Kind.allCases) { kind in
                Button {
                    tool = kind
                    editingTextID = nil
                } label: {
                    Label(kind.label, systemImage: kind.icon)
                        .labelStyle(.iconOnly)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .tint(tool == kind ? theme.accentColor : nil)
                .help(kind.help)
            }
            Divider().frame(height: 20)
            HStack(spacing: 4) {
                ForEach(Array(AnnotationPalette.colors.enumerated()), id: \.offset) { index, color in
                    Button {
                        colorIndex = index
                        if let selectedID, let i = annotations.firstIndex(where: { $0.id == selectedID }) {
                            annotations[i].colorIndex = index
                        }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(colorIndex == index ? Color.primary : Color.secondary.opacity(0.4), lineWidth: colorIndex == index ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .help("Colour of new marks (and of the selected one)")
            Picker("Width", selection: $lineWidth) {
                Text("Thin").tag(CGFloat(2))
                Text("Normal").tag(CGFloat(4))
                Text("Thick").tag(CGFloat(7))
            }
            .labelsHidden()
            .frame(width: 90)
            .onChange(of: lineWidth) { _, width in
                if let selectedID, let i = annotations.firstIndex(where: { $0.id == selectedID }) {
                    annotations[i].lineWidth = width
                }
            }
            Spacer()
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(annotations.isEmpty)
            .help("Undo (⌘Z)")
            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(undone.isEmpty)
            .help("Redo (⌘⇧Z)")
            Button {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedID == nil)
            .help("Remove the selected mark (⌘⌫)")
        }
        .padding(10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let image {
                Text("\(image.width) × \(image.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(tool.help)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Toggle("Replace original", isOn: $replaceOriginal)
                .toggleStyle(.checkbox)
                .help("Off: save as <name>-annotated.png next to the original and link that in the finding. On: overwrite the file — the blurred/redacted parts are gone for good.")
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(image == nil)
        }
        .padding(10)
    }

    // MARK: - Canvas

    private func canvas(image: CGImage, fit: CGRect) -> some View {
        let scale = fit.width / CGFloat(image.width)
        return Canvas { context, size in
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            for annotation in annotations + (draft.map { [$0] } ?? []) {
                drawPreview(annotation, context: &context, scale: scale, size: size)
            }
            if let selectedID, let selected = annotations.first(where: { $0.id == selectedID }) {
                let hit = selected.hitRect(fontSize: fontSize)
                let r = CGRect(x: hit.minX * scale, y: hit.minY * scale, width: hit.width * scale, height: hit.height * scale)
                context.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    private func drawPreview(_ annotation: ImageAnnotation, context: inout GraphicsContext, scale: CGFloat, size: CGSize) {
        let color = Color(nsColor: AnnotationPalette.color(annotation.colorIndex))
        let rect = annotation.rect
        let viewRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let width = max(annotation.lineWidth * scale, 1)
        switch annotation.kind {
        case .blur:
            guard viewRect.width > 0, viewRect.height > 0 else { return }
            if let pixelated {
                var clipped = context
                clipped.clip(to: Path(viewRect))
                clipped.draw(Image(decorative: pixelated, scale: 1), in: CGRect(origin: .zero, size: size))
            } else {
                context.fill(Path(viewRect), with: .color(.gray.opacity(0.8)))
            }
            context.stroke(Path(viewRect), with: .color(.white.opacity(0.5)), lineWidth: 1)
        case .redact:
            context.fill(Path(viewRect), with: .color(.black))
        case .highlight:
            context.fill(Path(viewRect), with: .color(color.opacity(0.35)))
        case .rectangle:
            context.stroke(Path(viewRect.insetBy(dx: width / 2, dy: width / 2)), with: .color(color), lineWidth: width)
        case .ellipse:
            context.stroke(Path(ellipseIn: viewRect.insetBy(dx: width / 2, dy: width / 2)), with: .color(color), lineWidth: width)
        case .arrow:
            let from = CGPoint(x: annotation.start.x * scale, y: annotation.start.y * scale)
            let to = CGPoint(x: annotation.end.x * scale, y: annotation.end.y * scale)
            let path = ImageAnnotationRenderer.arrowPath(from: from, to: to, lineWidth: width)
            context.stroke(Path(path.line), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            context.fill(Path(path.head), with: .color(color))
        case .text:
            let label = annotation.text.isEmpty ? "Text" : annotation.text
            let textSize = ImageAnnotationRenderer.textSize(label, fontSize: fontSize)
            let box = CGRect(x: annotation.start.x * scale, y: annotation.start.y * scale,
                             width: (textSize.width + 16) * scale, height: (textSize.height + 10) * scale)
            context.fill(Path(roundedRect: box, cornerRadius: 6 * scale), with: .color(color.opacity(0.92)))
            let text = Text(label).font(.system(size: fontSize * scale, weight: .semibold)).foregroundStyle(.white)
            context.draw(text, at: CGPoint(x: box.minX + 8 * scale, y: box.midY), anchor: .leading)
        }
    }

    // MARK: - Geometry

    private func fitRect(image: CGImage, in size: CGSize) -> CGRect {
        let inset: CGFloat = 12
        let available = CGSize(width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
        let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height), 1)
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// View point (in the "annotator" coordinate space, which holds the whole grey area) → image pixels.
    private func toImage(_ point: CGPoint, fit: CGRect) -> CGPoint {
        guard let image else { return point }
        let scale = CGFloat(image.width) / fit.width
        return CGPoint(x: min(max((point.x - fit.minX) * scale, 0), CGFloat(image.width)),
                       y: min(max((point.y - fit.minY) * scale, 0), CGFloat(image.height)))
    }

    private func toView(_ point: CGPoint, fit: CGRect) -> CGPoint {
        guard let image else { return point }
        let scale = fit.width / CGFloat(image.width)
        return CGPoint(x: fit.minX + point.x * scale, y: fit.minY + point.y * scale)
    }

    // MARK: - Gestures

    private func dragGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annotator"))
            .onChanged { value in
                let point = toImage(value.location, fit: fit)
                if dragOrigin == nil {
                    // Start: hit an existing mark (any tool) → select and move it; otherwise draw.
                    let origin = toImage(value.startLocation, fit: fit)
                    dragOrigin = origin
                    if editingTextID != nil { commitText() }
                    if let hit = annotations.last(where: { $0.hitRect(fontSize: fontSize).contains(origin) }) {
                        selectedID = hit.id
                        dragSelectionStart = hit
                        colorIndex = hit.colorIndex
                        if hit.kind != .text && hit.kind != .blur && hit.kind != .redact && hit.kind != .highlight {
                            lineWidth = hit.lineWidth
                        }
                        return
                    }
                    selectedID = nil
                    dragSelectionStart = nil
                    if tool == .text {
                        return
                    }
                    draft = ImageAnnotation(kind: tool, start: origin, end: origin, colorIndex: colorIndex, lineWidth: lineWidth)
                    return
                }
                guard let origin = dragOrigin else { return }
                if let start = dragSelectionStart, let index = annotations.firstIndex(where: { $0.id == start.id }) {
                    annotations[index] = start.moved(by: CGSize(width: point.x - origin.x, height: point.y - origin.y))
                } else if draft != nil {
                    draft?.end = point
                }
            }
            .onEnded { value in
                defer { dragOrigin = nil; dragSelectionStart = nil; draft = nil }
                guard let origin = dragOrigin else { return }
                if dragSelectionStart != nil {
                    // A plain click on a text label re-opens its editor.
                    if let selectedID, let selected = annotations.first(where: { $0.id == selectedID }),
                       selected.kind == .text, abs(value.translation.width) < 3, abs(value.translation.height) < 3 {
                        beginEditingText(selected.id)
                    }
                    return
                }
                if tool == .text {
                    let annotation = ImageAnnotation(kind: .text, start: origin, end: origin, colorIndex: colorIndex, lineWidth: lineWidth)
                    annotations.append(annotation)
                    undone.removeAll()
                    beginEditingText(annotation.id)
                    return
                }
                guard var finished = draft else { return }
                finished.end = toImage(value.location, fit: fit)
                let big = finished.rect.width >= 4 || finished.rect.height >= 4
                guard big else { return }
                annotations.append(finished)
                undone.removeAll()
                selectedID = finished.id
            }
    }

    private func beginEditingText(_ id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        textDraft = annotation.text
        editingTextID = id
        selectedID = id
        DispatchQueue.main.async { textFocused = true }
    }

    private func commitText() {
        guard let editingTextID else { return }
        if let index = annotations.firstIndex(where: { $0.id == editingTextID }) {
            annotations[index].text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if annotations[index].text.isEmpty { annotations.remove(at: index); selectedID = nil }
        }
        self.editingTextID = nil
        textDraft = ""
    }

    private func cancelText() {
        if let editingTextID, let index = annotations.firstIndex(where: { $0.id == editingTextID }), annotations[index].text.isEmpty {
            annotations.remove(at: index)
            selectedID = nil
        }
        editingTextID = nil
        textDraft = ""
    }

    private func undo() {
        guard let last = annotations.popLast() else { return }
        undone.append(last)
        if selectedID == last.id { selectedID = nil }
        if editingTextID == last.id { editingTextID = nil }
    }

    private func redo() {
        guard let last = undone.popLast() else { return }
        annotations.append(last)
    }

    private func deleteSelected() {
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        if editingTextID == selectedID { editingTextID = nil }
        undone.append(annotations.remove(at: index))
        self.selectedID = nil
    }

    // MARK: - Files

    private func load() {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
            error = "Could not open \(url.lastPathComponent)"
            return
        }
        image = cg
        DispatchQueue.global(qos: .userInitiated).async {
            let coarse = ImageAnnotationRenderer.pixelated(cg, block: ImageAnnotationRenderer.blockSize(for: cg))
            DispatchQueue.main.async { pixelated = coarse }
        }
    }

    private func save() {
        guard let image else { return }
        if editingTextID != nil { commitText() }
        guard let data = ImageAnnotationRenderer.render(image, annotations: annotations, fontSize: fontSize) else {
            error = "Could not render the image"
            return
        }
        let target: URL
        if replaceOriginal {
            target = url.pathExtension.lowercased() == "png" ? url : url.deletingPathExtension().appendingPathExtension("png")
        } else {
            let base = url.deletingPathExtension().lastPathComponent
            let stem = base.hasSuffix("-annotated") ? base : base + "-annotated"
            target = url.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension("png")
        }
        do {
            try data.write(to: target, options: .atomic)
            let kinds = Set(annotations.map { $0.kind })
            var what: [String] = []
            if kinds.contains(.blur) { what.append("blurred") }
            if kinds.contains(.redact) { what.append("redacted") }
            if !kinds.isDisjoint(with: [.arrow, .rectangle, .ellipse, .text, .highlight]) { what.append("annotated") }
            ActivityLog.shared.record(.evidence, "Screenshot \(what.joined(separator: ", ")): \(target.lastPathComponent)\(replaceOriginal ? " (original replaced)" : "")", source: "Findings")
            onSave(target)
            dismiss()
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
    }
}

private struct AnnotationTarget: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Thumbnails of the images linked under Evidence; click one to annotate it.
struct EvidenceImageStrip: View {
    @Binding var evidence: String
    @State private var annotating: AnnotationTarget?
    @State private var thumbnails: [String: NSImage] = [:]

    private var paths: [String] { EvidenceImages.paths(in: evidence) }

    var body: some View {
        let paths = self.paths
        if !paths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        thumbnail(path)
                    }
                }
                .padding(.vertical, 2)
            }
            .sheet(item: $annotating) { target in
                ImageAnnotatorView(url: target.url) { saved in
                    replace(path: target.url.path, with: saved.path)
                }
            }
            .onChange(of: paths) { _, _ in loadThumbnails() }
            .onAppear(perform: loadThumbnails)
        }
    }

    @ViewBuilder
    private func thumbnail(_ path: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: path)
        Button {
            if exists { annotating = AnnotationTarget(url: URL(fileURLWithPath: path)) }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.3))
                    if let image = thumbnails[path] {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                    } else {
                        Image(systemName: exists ? "photo" : "questionmark.square.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 76)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Text((path as NSString).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 120)
            }
        }
        .buttonStyle(.plain)
        .help(exists ? "Annotate, blur or redact \(path)" : "File not found: \(path)")
        .contextMenu {
            Button("Annotate…") { if exists { annotating = AnnotationTarget(url: URL(fileURLWithPath: path)) } }
                .disabled(!exists)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                .disabled(!exists)
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            Divider()
            Button("Remove link from evidence", role: .destructive) { removeLink(path) }
        }
    }

    private func loadThumbnails() {
        let wanted = paths
        DispatchQueue.global(qos: .utility).async {
            var loaded: [String: NSImage] = [:]
            for path in wanted {
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { continue }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceThumbnailMaxPixelSize: 240,
                                                kCGImageSourceCreateThumbnailWithTransform: true]
                if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    loaded[path] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
            DispatchQueue.main.async { thumbnails = loaded }
        }
    }

    /// Point the evidence link at the saved file (a copy gets linked instead of the original).
    private func replace(path old: String, with new: String) {
        guard old != new else { thumbnails[new] = nil; loadThumbnails(); return }
        if evidence.contains(old) {
            evidence = evidence.replacingOccurrences(of: old, with: new)
        } else {
            if !evidence.isEmpty && !evidence.hasSuffix("\n") { evidence += "\n" }
            evidence += "![evidence](\(new))\n"
        }
    }

    private func removeLink(_ path: String) {
        let lines = evidence.components(separatedBy: "\n")
        let kept = lines.filter { !$0.contains(path) }
        evidence = kept.joined(separator: "\n")
    }
}
