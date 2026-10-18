import AppKit
import SwiftUI

/// One right-click layer over the whole canvas instead of a `.contextMenu` per node: on macOS the
/// per-view context menu keeps an AppKit layer of its own that lags behind a moving SwiftUI view
/// (the "ghost" next to a dragged node). This view only claims right clicks; everything else
/// passes through to the canvas underneath.
struct DiagramContextMenuLayer: NSViewRepresentable {
    /// Builds the menu for a point in canvas coordinates (top-left origin, zoomed).
    var menu: (CGPoint) -> NSMenu?

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.menuProvider = menu
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.menuProvider = menu
    }

    final class RightClickView: NSView {
        var menuProvider: ((CGPoint) -> NSMenu?)?

        override var isFlipped: Bool { true }

        /// Only a right click (or control-click) lands here; left clicks go to SwiftUI.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            showMenu(for: event)
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                showMenu(for: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        private func showMenu(for event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let menu = menuProvider?(point) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

/// NSMenuItem with a closure, so the menu can be built from SwiftUI state.
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(_ title: String, state: NSControl.StateValue = .off, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(run), keyEquivalent: "")
        self.handler = handler
        self.target = self
        self.state = state
    }

    @objc private func run() {
        handler?()
    }
}

extension DiagramCanvas {
    /// What is under a point: topmost node first, then a link, then the smallest zone.
    enum CanvasHit {
        case node(DiagramNode)
        case link(DiagramLink)
        case zone(DiagramZone)
        case background
    }

    func hit(at point: CGPoint, in diagram: Diagram, zoom: CGFloat) -> CanvasHit {
        let geometry = DiagramGeometry(zoom: zoom)
        let p = geometry.toDiagram(point)
        if let node = diagram.nodes.last(where: { node in
            abs(node.x - p.x) <= Double(DiagramMetrics.nodeWidth) / 2 && abs(node.y - p.y) <= Double(DiagramMetrics.nodeHeight) / 2
        }) {
            return .node(node)
        }
        for link in diagram.links.reversed() {
            guard let a = diagram.node(link.from), let b = diagram.node(link.to) else { continue }
            let ca = geometry.point(a.x, a.y), cb = geometry.point(b.x, b.y)
            if DiagramCanvas.distance(from: point, toSegment: geometry.edgePoint(from: ca, toward: cb), geometry.edgePoint(from: cb, toward: ca)) <= 8 {
                return .link(link)
            }
        }
        if let zone = diagram.zones.filter({ $0.contains(x: p.x, y: p.y) }).min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return .zone(zone)
        }
        return .background
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        guard length2 > 0.001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The context menu for a right click at `point` (canvas coordinates).
    func contextMenu(at point: CGPoint, diagram: Diagram, zoom: CGFloat, store: DiagramStore) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch hit(at: point, in: diagram, zoom: zoom) {
        case .node(let node):
            store.selection = .node(node.id)
            let kindMenu = NSMenu()
            for group in DiagramNodeKind.groups {
                let header = NSMenuItem(title: group, action: nil, keyEquivalent: "")
                header.isEnabled = false
                kindMenu.addItem(header)
                for kind in DiagramNodeKind.allCases where kind.group == group {
                    let item = ClosureMenuItem("   " + kind.title, state: node.kind == kind ? .on : .off) {
                        store.checkpoint()
                        store.update { d in
                            if let i = d.nodes.firstIndex(where: { $0.id == node.id }) {
                                if d.nodes[i].label == d.nodes[i].kind.title { d.nodes[i].label = kind.title }
                                d.nodes[i].kind = kind
                            }
                        }
                    }
                    item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                    kindMenu.addItem(item)
                }
            }
            let kindItem = NSMenuItem(title: "Kind", action: nil, keyEquivalent: "")
            kindItem.submenu = kindMenu
            menu.addItem(kindItem)
            menu.addItem(ClosureMenuItem("Link from here…") {
                store.connectMode = true
                store.connectFrom = node.id
                store.selection = .node(node.id)
            })
            menu.addItem(ClosureMenuItem("Duplicate") {
                store.selection = .node(node.id)
                store.duplicateSelectedNode()
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Delete") {
                store.selection = .node(node.id)
                store.deleteSelection()
            })
        case .link(let link):
            store.selection = .link(link.id)
            let styleMenu = NSMenu()
            for style in DiagramLinkStyle.allCases {
                styleMenu.addItem(ClosureMenuItem(style.title, state: link.style == style ? .on : .off) {
                    store.checkpoint()
                    store.update { d in
                        if let i = d.links.firstIndex(where: { $0.id == link.id }) { d.links[i].style = style }
                    }
                })
            }
            let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
            styleItem.submenu = styleMenu
            menu.addItem(styleItem)
            menu.addItem(ClosureMenuItem(link.directed ? "Remove arrow" : "Add arrow") {
                store.checkpoint()
                store.update { d in
                    if let i = d.links.firstIndex(where: { $0.id == link.id }) { d.links[i].directed.toggle() }
                }
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Delete link") {
                store.selection = .link(link.id)
                store.deleteSelection()
            })
        case .zone(let zone):
            store.selection = .zone(zone.id)
            let p = DiagramGeometry(zoom: zoom).toDiagram(point)
            store.insertPoint = p
            menu.addItem(addNodeMenuItem(at: p, store: store))
            menu.addItem(ClosureMenuItem("Send to back") { store.bringZoneToBack(zone.id) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Delete zone") {
                store.selection = .zone(zone.id)
                store.deleteSelection()
            })
        case .background:
            store.selection = nil
            let p = DiagramGeometry(zoom: zoom).toDiagram(point)
            store.insertPoint = p
            menu.addItem(addNodeMenuItem(at: p, store: store))
            menu.addItem(ClosureMenuItem("Add zone here") { store.addZone(near: p) })
        }
        return menu
    }

    private func addNodeMenuItem(at point: CGPoint, store: DiagramStore) -> NSMenuItem {
        let addMenu = NSMenu()
        for group in DiagramNodeKind.groups {
            let header = NSMenuItem(title: group, action: nil, keyEquivalent: "")
            header.isEnabled = false
            addMenu.addItem(header)
            for kind in DiagramNodeKind.allCases where kind.group == group {
                let item = ClosureMenuItem("   " + kind.title) {
                    _ = store.addNode(kind, near: point)
                }
                item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                addMenu.addItem(item)
            }
        }
        let item = NSMenuItem(title: "Add node here", action: nil, keyEquivalent: "")
        item.submenu = addMenu
        return item
    }
}
