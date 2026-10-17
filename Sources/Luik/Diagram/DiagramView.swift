import AppKit
import SwiftUI

/// The Diagram tab: network architecture drawings per engagement.
struct DiagramView: View {
    @Environment(DiagramStore.self) private var store
    @Environment(\.luikTheme) private var theme
    @State private var status: String?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let diagram = store.current {
                HStack(spacing: 0) {
                    DiagramCanvas(diagram: diagram)
                    if store.selection != nil {
                        Divider()
                        DiagramInspector(diagram: diagram)
                            .frame(width: 260)
                    }
                }
                Divider()
                statusBar(diagram)
            } else {
                emptyState
            }
        }
        .alert("Rename diagram", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = store.currentID, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(id, to: renameText.trimmingCharacters(in: .whitespaces))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(store.current?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.deleteCurrent() }
        } message: {
            Text("Export it first if you may need it again.")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
            Menu {
                ForEach(store.diagrams) { diagram in
                    Button {
                        store.select(diagram.id)
                    } label: {
                        if diagram.id == store.currentID {
                            Label(diagram.name, systemImage: "checkmark")
                        } else {
                            Text(diagram.name)
                        }
                    }
                }
                if !store.diagrams.isEmpty { Divider() }
                Button("New diagram") { store.newDiagram() }
                Button("New from example: network") { store.newDiagram(name: "Example network", sample: true) }
                Button("New from example: web application") { store.newDiagram(name: "Example web application", webApp: true) }
                if store.current != nil {
                    Divider()
                    Button("Rename…") {
                        renameText = store.current?.name ?? ""
                        renaming = true
                    }
                    Button("Duplicate") { store.duplicateCurrent() }
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Label(store.current?.name ?? "Diagrams", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .frame(maxWidth: 200)

            if store.current != nil {
                Divider().frame(height: 18)
                addMenu
                ForEach([DiagramNodeKind.firewall, .router, .switchDevice, .server, .workstation, .webApp, .api, .identityProvider], id: \.self) { kind in
                    Button {
                        addNode(kind)
                    } label: {
                        Image(systemName: kind.symbol)
                            .foregroundStyle(kind.color)
                    }
                    .help("Add \(kind.title.lowercased())")
                }
                Button {
                    store.addZone(near: store.insertPoint ?? defaultInsertPoint)
                } label: {
                    Label("Zone", systemImage: "rectangle.dashed")
                }
                .help("Add a network segment (DMZ, LAN, VLAN, VNet): drag it around, drag the corner to resize; the nodes inside move with it")
                Toggle(isOn: $store.connectMode) {
                    Label("Connect", systemImage: "link")
                }
                .toggleStyle(.button)
                .onChange(of: store.connectMode) { _, _ in store.connectFrom = nil }
                .help("Click a node, then another, to link them. Or drag the dot on the right of a selected node to another node.")
                Menu {
                    Button("Add missing hosts to this diagram") {
                        let added = store.addHostsFromTargets()
                        status = added == 0 ? "Every host in Targets is in the diagram already (matched on address)." : "Added \(added) host(s) from Targets."
                    }
                    Button("Build a network map (new diagram)") {
                        let placed = store.buildNetworkMap()
                        status = placed == 0 ? "No hosts in Targets yet." : "Network map: \(placed) host(s) grouped by /24, with gateways and your attacker node."
                    }
                } label: {
                    Label("From Targets", systemImage: "network")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add the hosts of the Targets tab as nodes, or build a complete map: a zone per /24, a gateway per segment, the attacker node linked to the gateways; kinds guessed from the open ports")
                Button {
                    store.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(store.undoDepth == 0)
                .help("Undo the last change to the drawing")
            }

            Spacer()

            if store.current != nil {
                zoomControls
            }
            Menu {
                Button("Import file…") {
                    status = DiagramTransfer.importWithPanel(into: store)
                }
                Button("Paste Mermaid / draw.io from clipboard") {
                    status = DiagramTransfer.importFromClipboard(into: store)
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .frame(width: 92)
            .help("draw.io (.drawio, also compressed), Mermaid flowcharts and Luik JSON")
            if let diagram = store.current {
                Menu {
                    ForEach(DiagramTransfer.ExportFormat.allCases) { format in
                        Button(format.title) {
                            export(diagram, format)
                        }
                    }
                    Divider()
                    Button("Copy image (light)") { copyImage(diagram, light: true) }
                    Button("Copy image (dark)") { copyImage(diagram, light: false) }
                    Divider()
                    Button("Save to Library (PNG, light)") { saveToLibrary(diagram) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .frame(width: 92)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var addMenu: some View {
        Menu {
            ForEach(DiagramNodeKind.groups, id: \.self) { group in
                Section(group) {
                    ForEach(DiagramNodeKind.allCases.filter { $0.group == group }) { kind in
                        Button {
                            addNode(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .frame(width: 70)
        .help("Add a device. It appears where you last clicked on the canvas.")
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                store.zoom = max(0.4, ((store.zoom - 0.1) * 10).rounded() / 10)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            Text("\(Int((store.zoom * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40)
            Button {
                store.zoom = min(2.0, ((store.zoom + 0.1) * 10).rounded() / 10)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            Button("Fit") { store.fitToViewport() }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Zoom so the whole diagram is visible")
        }
        .foregroundStyle(.secondary)
    }

    /// Right of what is there, near the top — when nothing was clicked yet.
    private var defaultInsertPoint: CGPoint {
        guard let diagram = store.current, !diagram.nodes.isEmpty || !diagram.zones.isEmpty else { return CGPoint(x: 200, y: 140) }
        let bounds = diagram.bounds
        return CGPoint(x: bounds.maxX + 120, y: max(bounds.minY + 40, 80))
    }

    private func addNode(_ kind: DiagramNodeKind) {
        store.addNode(kind, near: store.insertPoint ?? defaultInsertPoint)
    }

    @MainActor
    private func export(_ diagram: Diagram, _ format: DiagramTransfer.ExportFormat) {
        status = DiagramTransfer.export(diagram, as: format, accent: theme.accentColor)
    }

    @MainActor
    /// A light PNG of the drawing into the library's Images collection (next to the HLDs).
    private func saveToLibrary(_ diagram: Diagram) {
        guard let data = DiagramTransfer.png(diagram, palette: .light(accent: theme.accentColor)) else {
            status = "Could not render the image."
            return
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let slug = diagram.name.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        if let id = LibraryStore.shared.saveImage(data: data, name: "\(slug)-\(stamp.string(from: Date())).png") {
            status = "Saved to the library as \(id)."
        } else {
            status = LibraryStore.shared.lastError ?? "Could not save to the library."
        }
    }

    private func copyImage(_ diagram: Diagram, light: Bool) {
        status = DiagramTransfer.copyImage(diagram, accent: theme.accentColor, light: light)
            ? "Image copied — paste it into a report, mail or chat." : "Could not render the image."
    }

    // MARK: Status

    private func statusBar(_ diagram: Diagram) -> some View {
        HStack(spacing: 10) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(store.connectMode ? theme.accentColor : Color.secondary)
                .lineLimit(1)
            Spacer()
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("\(diagram.nodes.count) nodes · \(diagram.links.count) links · \(diagram.zones.count) zones")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var hint: String {
        if store.connectMode {
            return store.connectFrom == nil ? "Connect: click the first node (esc to stop)." : "Connect: now click the node to link it to."
        }
        switch store.selection {
        case .node: return "Drag to move · drag the dot on the right to another node to link · ⌫ deletes · right-click for more"
        case .zone: return "Drag to move (with its nodes) · drag the corner to resize · ⌫ deletes"
        case .link: return "Edit the label, style and direction on the right · ⌫ deletes"
        case nil: return "Click the canvas to choose where new nodes go · Add or the icons above add devices"
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No diagrams in this engagement yet.")
                .font(.headline)
            Text("Draw the network architecture: firewalls, segments, servers and clients, with links between them. Export as PNG or SVG for the report, or as draw.io / Mermaid to edit elsewhere; import those formats too.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    store.newDiagram()
                } label: {
                    Label("New diagram", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button("Start from the network example") { store.newDiagram(name: "Example network", sample: true) }
                Button("Start from the web application example") { store.newDiagram(name: "Example web application", webApp: true) }
                Button("Network map from Targets") {
                    let placed = store.buildNetworkMap()
                    status = placed == 0 ? "No hosts in Targets yet." : "Network map: \(placed) host(s) grouped by /24."
                }
                Button("Import…") { status = DiagramTransfer.importWithPanel(into: store) }
            }
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Canvas

struct DiagramCanvas: View {
    let diagram: Diagram
    @Environment(DiagramStore.self) private var store
    @Environment(\.luikTheme) private var theme

    private struct ZoneDrag {
        let id: UUID
        let start: CGPoint
        let nodes: [UUID: CGPoint]
    }

    @State private var nodeDragStart: [UUID: CGPoint] = [:]
    @State private var zoneDrag: ZoneDrag?
    @State private var resizeStart: CGSize?
    @State private var pendingLink: (from: UUID, to: CGPoint)?
    @State private var hoverTarget: UUID?

    private var zoom: CGFloat { CGFloat(store.zoom) }
    private var geometry: DiagramGeometry { DiagramGeometry(zoom: zoom) }
    private var palette: DiagramPalette { .dark(accent: theme.accentColor) }

    var body: some View {
        GeometryReader { proxy in
            let bounds = diagram.bounds
            let width = max(proxy.size.width, (bounds.maxX + 400) * zoom)
            let height = max(proxy.size.height, (bounds.maxY + 300) * zoom)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    background
                    DiagramGridView(zoom: zoom, color: palette.grid)
                        .allowsHitTesting(false)
                    ForEach(diagram.zones) { zone in
                        zoneView(zone)
                    }
                    ForEach(diagram.links) { link in
                        linkView(link)
                    }
                    pendingLinkView
                    ForEach(diagram.nodes) { node in
                        nodeView(node)
                    }
                    selectionHandles
                }
                .frame(width: width, height: height)
                .coordinateSpace(name: "diagram")
            }
            .onAppear { store.viewportSize = proxy.size }
            .onChange(of: proxy.size) { _, size in store.viewportSize = size }
        }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { store.deleteSelection() }
        .onExitCommand {
            if store.connectMode {
                store.connectMode = false
            } else {
                store.selection = nil
            }
        }
    }

    // MARK: Layers

    private var background: some View {
        palette.background
            .contentShape(Rectangle())
            .onTapGesture { location in
                store.selection = nil
                store.connectFrom = nil
                store.insertPoint = geometry.toDiagram(location)
            }
    }

    private func zoneView(_ zone: DiagramZone) -> some View {
        let selected = store.selection == .zone(zone.id)
        let center = geometry.point(zone.x + zone.width / 2, zone.y + zone.height / 2)
        return DiagramZoneView(zone: zone, zoom: zoom, palette: palette, selected: selected)
            .contentShape(Rectangle())
            .onTapGesture { location in
                store.selection = .zone(zone.id)
                store.insertPoint = CGPoint(x: zone.x + Double(location.x / zoom), y: zone.y + Double(location.y / zoom))
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if zoneDrag?.id != zone.id {
                            store.checkpoint()
                            let current = store.current ?? diagram
                            let live = current.zones.first { $0.id == zone.id } ?? zone
                            var inside: [UUID: CGPoint] = [:]
                            for node in current.nodes where live.contains(x: node.x, y: node.y) {
                                inside[node.id] = CGPoint(x: node.x, y: node.y)
                            }
                            zoneDrag = ZoneDrag(id: zone.id, start: CGPoint(x: live.x, y: live.y), nodes: inside)
                            store.selection = .zone(zone.id)
                        }
                        guard let drag = zoneDrag else { return }
                        let target = CGPoint(x: DiagramMetrics.snap(Double(drag.start.x + value.translation.width / zoom)),
                                             y: DiagramMetrics.snap(Double(drag.start.y + value.translation.height / zoom)))
                        store.moveZone(zone.id, to: target, carrying: drag.nodes, zoneStart: drag.start)
                    }
                    .onEnded { _ in zoneDrag = nil }
            )
            .contextMenu {
                Button("Send to back") { store.bringZoneToBack(zone.id) }
                Divider()
                Button("Delete zone", role: .destructive) {
                    store.selection = .zone(zone.id)
                    store.deleteSelection()
                }
            }
            .position(center)
    }

    @ViewBuilder
    private func linkView(_ link: DiagramLink) -> some View {
        if let a = diagram.node(link.from), let b = diagram.node(link.to) {
            let ca = geometry.point(a.x, a.y)
            let cb = geometry.point(b.x, b.y)
            let from = geometry.edgePoint(from: ca, toward: cb)
            let to = geometry.edgePoint(from: cb, toward: ca)
            DiagramLinkView(from: from, to: to, link: link, zoom: zoom, palette: palette, selected: store.selection == .link(link.id))
                .contentShape(DiagramLineShape(from: from, to: to).path(in: .zero).strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round)))
                .onTapGesture { store.selection = .link(link.id) }
                .contextMenu {
                    Picker("Style", selection: Binding(get: { link.style }, set: { style in
                        store.checkpoint()
                        store.update { d in
                            if let i = d.links.firstIndex(where: { $0.id == link.id }) { d.links[i].style = style }
                        }
                    })) {
                        ForEach(DiagramLinkStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Button(link.directed ? "Remove arrow" : "Add arrow") {
                        store.checkpoint()
                        store.update { d in
                            if let i = d.links.firstIndex(where: { $0.id == link.id }) { d.links[i].directed.toggle() }
                        }
                    }
                    Divider()
                    Button("Delete link", role: .destructive) {
                        store.selection = .link(link.id)
                        store.deleteSelection()
                    }
                }
        }
    }

    @ViewBuilder
    private var pendingLinkView: some View {
        if let pending = pendingLink, let node = diagram.node(pending.from) {
            let center = geometry.point(node.x, node.y)
            DiagramLineShape(from: geometry.edgePoint(from: center, toward: pending.to), to: pending.to)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                .allowsHitTesting(false)
        }
    }

    private func nodeView(_ node: DiagramNode) -> some View {
        let selected = store.selection == .node(node.id)
        let highlighted = store.connectFrom == node.id || hoverTarget == node.id
        return DiagramNodeView(node: node, zoom: zoom, palette: palette, selected: selected, highlighted: highlighted)
            .help(node.notes.isEmpty ? "" : node.notes)
            .onTapGesture {
                if store.connectMode {
                    store.connectModeTap(node.id)
                } else {
                    store.selection = .node(node.id)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if nodeDragStart[node.id] == nil {
                            store.checkpoint()
                            let live = store.current?.node(node.id) ?? node
                            nodeDragStart[node.id] = CGPoint(x: live.x, y: live.y)
                            store.selection = .node(node.id)
                        }
                        guard let start = nodeDragStart[node.id] else { return }
                        store.moveNode(node.id, to: CGPoint(x: start.x + value.translation.width / zoom,
                                                            y: start.y + value.translation.height / zoom))
                    }
                    .onEnded { _ in
                        store.snapNode(node.id)
                        nodeDragStart[node.id] = nil
                    }
            )
            .contextMenu { nodeMenu(node) }
            .position(geometry.point(node.x, node.y))
    }

    @ViewBuilder
    private func nodeMenu(_ node: DiagramNode) -> some View {
        Menu("Kind") {
            ForEach(DiagramNodeKind.allCases) { kind in
                Button {
                    store.checkpoint()
                    store.update { d in
                        if let i = d.nodes.firstIndex(where: { $0.id == node.id }) {
                            // A label that was just the old kind's name follows the new kind.
                            if d.nodes[i].label == d.nodes[i].kind.title { d.nodes[i].label = kind.title }
                            d.nodes[i].kind = kind
                        }
                    }
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        }
        Button("Link from here…") {
            store.connectMode = true
            store.connectFrom = node.id
            store.selection = .node(node.id)
        }
        Button("Duplicate") {
            store.selection = .node(node.id)
            store.duplicateSelectedNode()
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.selection = .node(node.id)
            store.deleteSelection()
        }
    }

    /// The link dot on a selected node and the resize grip on a selected zone.
    @ViewBuilder
    private var selectionHandles: some View {
        switch store.selection {
        case .node(let id):
            if !store.connectMode, let node = diagram.node(id) {
                let anchor = geometry.point(node.x + Double(DiagramMetrics.nodeWidth) / 2 + 10, node.y)
                Circle()
                    .fill(palette.accent)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 13, height: 13)
                    .contentShape(Circle().inset(by: -6))
                    .help("Drag to another node to link them")
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("diagram"))
                            .onChanged { value in
                                pendingLink = (id, value.location)
                                hoverTarget = nodeAt(value.location, excluding: id)
                            }
                            .onEnded { value in
                                if let target = nodeAt(value.location, excluding: id) {
                                    store.connect(id, target)
                                }
                                pendingLink = nil
                                hoverTarget = nil
                            }
                    )
                    .position(anchor)
            }
        case .zone(let id):
            if let zone = diagram.zones.first(where: { $0.id == id }) {
                let corner = geometry.point(zone.x + zone.width, zone.y + zone.height)
                RoundedRectangle(cornerRadius: 3)
                    .fill(zone.color)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle().inset(by: -6))
                    .help("Drag to resize the zone")
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if resizeStart == nil {
                                    store.checkpoint()
                                    let live = store.current?.zones.first { $0.id == id } ?? zone
                                    resizeStart = CGSize(width: live.width, height: live.height)
                                }
                                guard let start = resizeStart else { return }
                                store.resizeZone(id, width: Double(start.width + value.translation.width / zoom),
                                                 height: Double(start.height + value.translation.height / zoom))
                            }
                            .onEnded { _ in
                                store.snapZone(id)
                                resizeStart = nil
                            }
                    )
                    .position(corner)
            }
        default:
            EmptyView()
        }
    }

    /// The node under a point in canvas coordinates.
    private func nodeAt(_ point: CGPoint, excluding: UUID) -> UUID? {
        let p = geometry.toDiagram(point)
        let current = store.current ?? diagram
        return current.nodes.last { node in
            node.id != excluding
                && abs(node.x - Double(p.x)) <= Double(DiagramMetrics.nodeWidth) / 2
                && abs(node.y - Double(p.y)) <= Double(DiagramMetrics.nodeHeight) / 2
        }?.id
    }
}

// MARK: - Inspector

struct DiagramInspector: View {
    let diagram: Diagram
    @Environment(DiagramStore.self) private var store
    @Environment(\.luikTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch store.selection {
                case .node(let id):
                    if let node = diagram.node(id) { nodeInspector(node) }
                case .link(let id):
                    if let link = diagram.links.first(where: { $0.id == id }) { linkInspector(link) }
                case .zone(let id):
                    if let zone = diagram.zones.first(where: { $0.id == id }) { zoneInspector(zone) }
                case nil:
                    EmptyView()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.headline)
            Spacer()
            Button {
                store.selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // Node

    private func nodeBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<DiagramNode, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.current?.node(id)?[keyPath: keyPath] ?? fallback },
            set: { value in
                store.update { d in
                    if let i = d.nodes.firstIndex(where: { $0.id == id }) { d.nodes[i][keyPath: keyPath] = value }
                }
            }
        )
    }

    @ViewBuilder
    private func nodeInspector(_ node: DiagramNode) -> some View {
        header("Node", symbol: node.kind.symbol)
        caption("Kind")
        Picker("", selection: Binding(get: { node.kind }, set: { kind in
            store.checkpoint()
            store.update { d in
                if let i = d.nodes.firstIndex(where: { $0.id == node.id }) {
                    if d.nodes[i].label == d.nodes[i].kind.title { d.nodes[i].label = kind.title }
                    d.nodes[i].kind = kind
                }
            }
        })) {
            ForEach(DiagramNodeKind.groups, id: \.self) { group in
                Section(group) {
                    ForEach(DiagramNodeKind.allCases.filter { $0.group == group }) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
            }
        }
        .labelsHidden()
        caption("Label")
        TextField("Name", text: nodeBinding(node.id, \.label, fallback: ""))
            .textFieldStyle(.roundedBorder)
        caption("Address")
        TextField("10.0.0.10, 10.0.20.0/24, host.local", text: nodeBinding(node.id, \.address, fallback: ""))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        caption("Notes (shown as tooltip)")
        TextEditor(text: nodeBinding(node.id, \.notes, fallback: ""))
            .font(.callout)
            .frame(minHeight: 70)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        let connected = diagram.links.filter { $0.from == node.id || $0.to == node.id }
        if !connected.isEmpty {
            caption("Links")
            ForEach(connected) { link in
                let otherID = link.from == node.id ? link.to : link.from
                Button {
                    store.selection = .link(link.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: link.directed ? (link.from == node.id ? "arrow.right" : "arrow.left") : "line.diagonal")
                            .foregroundStyle(.secondary)
                        Text(diagram.node(otherID)?.label ?? "?")
                            .lineLimit(1)
                        if !link.label.isEmpty {
                            Text(link.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        HStack {
            Button("Duplicate") { store.duplicateSelectedNode() }
            Spacer()
            Button("Delete", role: .destructive) { store.deleteSelection() }
        }
        .padding(.top, 4)
    }

    // Link

    private func linkBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<DiagramLink, T>, fallback: T, checkpoint: Bool = false) -> Binding<T> {
        Binding(
            get: { store.current?.links.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { value in
                if checkpoint { store.checkpoint() }
                store.update { d in
                    if let i = d.links.firstIndex(where: { $0.id == id }) { d.links[i][keyPath: keyPath] = value }
                }
            }
        )
    }

    @ViewBuilder
    private func linkInspector(_ link: DiagramLink) -> some View {
        header("Link", symbol: "link")
        Text("\(diagram.node(link.from)?.label ?? "?")  \(link.directed ? "→" : "—")  \(diagram.node(link.to)?.label ?? "?")")
            .font(.callout)
            .lineLimit(2)
        caption("Label (port, protocol, VLAN, …)")
        TextField("443/tcp, IPsec, VLAN 20", text: linkBinding(link.id, \.label, fallback: ""))
            .textFieldStyle(.roundedBorder)
        caption("Line")
        Picker("", selection: linkBinding(link.id, \.style, fallback: .solid, checkpoint: true)) {
            ForEach(DiagramLinkStyle.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        Toggle("Arrow (direction of traffic or trust)", isOn: linkBinding(link.id, \.directed, fallback: false, checkpoint: true))
        if link.directed {
            Button("Swap direction") {
                store.checkpoint()
                store.update { d in
                    if let i = d.links.firstIndex(where: { $0.id == link.id }) {
                        let from = d.links[i].from
                        d.links[i].from = d.links[i].to
                        d.links[i].to = from
                    }
                }
            }
        }
        HStack {
            Spacer()
            Button("Delete", role: .destructive) { store.deleteSelection() }
        }
        .padding(.top, 4)
    }

    // Zone

    private func zoneBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<DiagramZone, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.current?.zones.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { value in
                store.update { d in
                    if let i = d.zones.firstIndex(where: { $0.id == id }) { d.zones[i][keyPath: keyPath] = value }
                }
            }
        )
    }

    @ViewBuilder
    private func zoneInspector(_ zone: DiagramZone) -> some View {
        header("Zone", symbol: "rectangle.dashed")
        caption("Name")
        TextField("DMZ — 172.16.10.0/24", text: zoneBinding(zone.id, \.name, fallback: ""))
            .textFieldStyle(.roundedBorder)
        caption("Colour")
        HStack(spacing: 6) {
            ForEach(DiagramZone.palette, id: \.self) { hex in
                let color = Color(nsColor: NSColor(hex: hex))
                Button {
                    store.checkpoint()
                    store.update { d in
                        if let i = d.zones.firstIndex(where: { $0.id == zone.id }) { d.zones[i].colorHex = hex }
                    }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: zone.colorHex == hex ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
        }
        let members = diagram.nodes.filter { zone.contains(x: $0.x, y: $0.y) }
        caption(members.isEmpty ? "No nodes inside — drag nodes into the zone." : "\(members.count) node(s) inside; they move with the zone.")
        HStack {
            Button("Send to back") { store.bringZoneToBack(zone.id) }
            Spacer()
            Button("Delete", role: .destructive) { store.deleteSelection() }
        }
        .padding(.top, 4)
    }
}
