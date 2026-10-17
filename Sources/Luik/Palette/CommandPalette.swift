import AppKit
import SwiftUI

/// One row in the ⌘K palette.
struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let group: String
    let action: () -> Void
}

/// ⌘K: one search box over everything in Luik — actions, notes, one-liners, targets, knowledge
/// base, Exploit-DB, Chef operations and the activity log.
struct CommandPalette: View {
    @Environment(UIState.self) private var ui
    @Environment(NotesStore.self) private var notes
    @Environment(SnippetStore.self) private var snippets
    @Environment(TargetStore.self) private var targets
    @Environment(KnowledgeBaseStore.self) private var knowledge
    @Environment(ExploitStore.self) private var exploits
    @Environment(ChefStore.self) private var chef
    @Environment(ActivityLog.self) private var log
    @Environment(TerminalStore.self) private var terminals
    @Environment(FindingsStore.self) private var findings
    @Environment(EngagementStore.self) private var engagements

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var exploitItems: [PaletteItem] = []
    @State private var exploitQuery = ""
    @FocusState private var focused: Bool

    private static let perSource = 6

    var body: some View {
        let items = results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search everything… (notes, one-liners, targets, findings, exploits, operations, log, actions)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { activate(items) }
                    .onKeyPress(.downArrow) {
                        if !items.isEmpty { selectedIndex = min(selectedIndex + 1, items.count - 1) }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selectedIndex = max(selectedIndex - 1, 0)
                        return .handled
                    }
                Text("esc")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if items.isEmpty {
                Text(query.isEmpty ? "Type to search. ↑↓ to choose, ↩ to open." : "No matches.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || items[index - 1].group != item.group {
                                    Text(item.group)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.top, index == 0 ? 6 : 10)
                                        .padding(.bottom, 2)
                                }
                                PaletteRow(item: item, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture {
                                        selectedIndex = index
                                        activate(items)
                                    }
                                    .onHover { inside in
                                        if inside { selectedIndex = index }
                                    }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: selectedIndex) { _, index in
                        if index < items.count {
                            proxy.scrollTo(items[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 680)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onAppear {
            focused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, newValue in
            selectedIndex = 0
            searchExploits(newValue)
        }
        .onExitCommand { close() }
    }

    private func close() {
        ui.showPalette = false
    }

    private func activate(_ items: [PaletteItem]) {
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        close()
        item.action()
    }

    // MARK: - Sources

    private var terms: [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        return terms.allSatisfy { lower.contains($0) }
    }

    private var results: [PaletteItem] {
        var items: [PaletteItem] = []
        let q = query.trimmingCharacters(in: .whitespaces)

        // Actions
        let actions: [PaletteItem] = ui.tabOrder.map { module in
            PaletteItem(id: "go-\(module.rawValue)", icon: module.icon, title: "Go to \(module.title)", subtitle: "", group: "Actions") {
                ui.module = module
            }
        } + [
            PaletteItem(id: "new-tab", icon: "plus.rectangle", title: "New terminal tab", subtitle: "⌘T", group: "Actions") {
                ui.module = .terminal
                terminals.newSession()
            },
            PaletteItem(id: "settings", icon: "gearshape", title: "Settings", subtitle: "⌘,", group: "Actions") {
                ui.showSettings = true
            },
            PaletteItem(id: "evidence", icon: "camera", title: "Capture evidence screenshot", subtitle: "⌘⇧E", group: "Actions") {
                AppDelegate.shared?.captureEvidence(hideLuik: UserDefaults.standard.bool(forKey: SettingsKey.hideWhileCapturing))
            },
            PaletteItem(id: "new-finding", icon: "exclamationmark.triangle", title: "New finding", subtitle: "⌘N", group: "Actions") {
                ui.module = .findings
                findings.newFinding()
            },
            PaletteItem(id: "engagements", icon: "briefcase", title: "Manage engagements", subtitle: engagements.current.displayName, group: "Actions") {
                engagements.showManager = true
            },
            PaletteItem(id: "checklists", icon: "list.bullet.rectangle", title: "Edit checklists", subtitle: "work items per system, port and service", group: "Actions") {
                ChecklistStore.shared.showEditor = true
            },
            PaletteItem(id: "shortcuts", icon: "keyboard", title: "Keyboard shortcuts", subtitle: "⌘/", group: "Actions") {
                ui.showShortcuts = true
            },
            PaletteItem(id: "new-diagram", icon: "point.3.connected.trianglepath.dotted", title: "New network diagram", subtitle: "Diagram tab", group: "Actions") {
                ui.module = .diagram
                DiagramStore.shared.newDiagram()
            },
            PaletteItem(id: "version-check", icon: "clock.badge.exclamationmark", title: "Version & end-of-life check", subtitle: "endoflife.date cycles and dates, GitHub release notes", group: "Actions") {
                ui.tool = .versionCheck
                ui.module = .tools
            },
            PaletteItem(id: "new-plan", icon: "list.clipboard", title: "New plan from template", subtitle: "engagement test plan: phases, items, fields", group: "Actions") {
                ui.module = .plan
                PlanStore.shared.showNewPlan = true
            },
            PaletteItem(id: "plan-templates", icon: "list.clipboard", title: "Plan templates", subtitle: "edit, duplicate, export / import", group: "Actions") {
                ui.module = .plan
                PlanStore.shared.showTemplateEditor = true
            },
            PaletteItem(id: "reverse-shell", icon: "arrow.uturn.backward.circle", title: "Reverse shell generator", subtitle: "template from the library's cheat sheet, $LHOST/$LPORT, shell, encoding, listener, TTY upgrade", group: "Actions") {
                ui.showReverseShell = true
            },
            PaletteItem(id: "library-download", icon: "books.vertical", title: "Download documentation", subtitle: "PayloadsAllTheThings, InternalAllTheThings or your own repository into the library", group: "Actions") {
                ui.module = .notes
                ui.showLibrarySources = true
            },
            PaletteItem(id: "kb-download", icon: "icloud.and.arrow.down", title: "Download knowledge base", subtitle: "English or Dutch attack-vectors knowledge base from GitHub, or your own link", group: "Actions") {
                ui.module = .knowledgeBase
                ui.showKnowledgeBaseDownload = true
            },
            PaletteItem(id: "kb-template", icon: "tablecells", title: "Save knowledge-base template", subtitle: "example CSV with the recognised columns", group: "Actions") {
                KnowledgeBaseTemplate.save()
            },
            PaletteItem(id: "hide", icon: "chevron.up", title: "Hide Luik", subtitle: "", group: "Actions") {
                AppDelegate.shared?.hideDropdown()
            },
        ]
        items += actions.filter { q.isEmpty ? true : matches($0.title) }.prefix(q.isEmpty ? 4 : 6)
        guard !q.isEmpty else { return items }

        // Engagements (switching)
        items += engagements.engagements.filter { $0.id != engagements.currentID && matches($0.displayName + " " + $0.client + " " + $0.reference) }
            .prefix(4).map { engagement in
                PaletteItem(id: "eng-\(engagement.id)", icon: "briefcase", title: "Switch to \(engagement.displayName)",
                            subtitle: engagement.client, group: "Engagements") {
                    engagements.switchTo(engagement.id)
                }
            }

        // Targets
        var targetItems: [PaletteItem] = []
        func walk(_ node: TargetNode, path: [String]) {
            let fullPath = path + [node.title]
            if matches(node.title + " " + node.subtitle + " " + node.notes) {
                targetItems.append(PaletteItem(id: "target-\(node.id)", icon: node.kind.symbol,
                                               title: fullPath.joined(separator: " › "),
                                               subtitle: node.subtitle, group: "Targets") {
                    targets.selectedID = node.id
                    ui.module = .targets
                })
            }
            for child in node.children { walk(child, path: fullPath) }
        }
        for host in targets.hosts { walk(host, path: []) }
        items += targetItems.prefix(CommandPalette.perSource)

        // Findings
        items += findings.sorted.filter { matches($0.title + " " + $0.description + " " + $0.affected.joined(separator: " ") + " " + $0.source) }
            .prefix(CommandPalette.perSource).map { finding in
                PaletteItem(id: "finding-\(finding.id)", icon: "exclamationmark.triangle", title: finding.title.isEmpty ? "Untitled finding" : finding.title,
                            subtitle: "\(finding.severity.label) · \(finding.affected.prefix(3).joined(separator: ", "))", group: "Findings") {
                    findings.selectedID = finding.id
                    ui.module = .findings
                }
            }

        // Notes
        items += notes.notes.filter { matches($0.title + " " + $0.body) }.prefix(CommandPalette.perSource).map { note in
            PaletteItem(id: "note-\(note.id)", icon: "note.text", title: note.title.isEmpty ? "Untitled" : note.title,
                        subtitle: String(note.body.prefix(80)).replacingOccurrences(of: "\n", with: " "), group: "Notes") {
                notes.selectedID = note.id
                ui.module = .notes
            }
        }

        // Diagrams: by name, or by a node's label / address.
        for diagram in DiagramStore.shared.diagrams {
            let hit = matches(diagram.name) ? nil : diagram.nodes.first { matches($0.label + " " + $0.address) }
            guard matches(diagram.name) || hit != nil else { continue }
            items.append(PaletteItem(id: "diagram-\(diagram.id)", icon: "point.3.connected.trianglepath.dotted", title: diagram.name,
                                     subtitle: hit.map { "contains \($0.label) \($0.address)" } ?? "\(diagram.nodes.count) nodes", group: "Diagrams") {
                DiagramStore.shared.select(diagram.id)
                if let hit { DiagramStore.shared.selection = .node(hit.id) }
                ui.module = .diagram
            })
        }

        // Plan items of this engagement.
        for plan in PlanStore.shared.plans {
            for phase in plan.phases {
                for item in phase.items where matches(item.title + " " + phase.name + " " + item.notes) {
                    items.append(PaletteItem(id: "plan-item-\(item.id)", icon: item.status.symbol, title: item.title,
                                             subtitle: "\(plan.name) › \(phase.name) · \(item.status.label)", group: "Plan") {
                        PlanStore.shared.selectedPlanID = plan.id
                        PlanStore.shared.selectedPhaseID = phase.id
                        ui.module = .plan
                    })
                    if items.filter({ $0.group == "Plan" }).count >= CommandPalette.perSource { break }
                }
            }
        }

        // Library (cheat sheets, PayloadsAllTheThings, …): titles first, then full text.
        items += LibraryStore.shared.search(q, limit: CommandPalette.perSource).map { document in
            PaletteItem(id: "library-\(document.id)", icon: "books.vertical", title: document.title,
                        subtitle: document.breadcrumb, group: "Library") {
                notes.open(document)
                ui.module = .notes
            }
        }

        // One-liners
        items += snippets.snippets.filter { matches($0.searchText) }.prefix(CommandPalette.perSource).map { snippet in
            PaletteItem(id: "snippet-\(snippet.id)", icon: "doc.on.clipboard", title: snippet.title,
                        subtitle: snippets.resolve(snippet.command), group: "One-liners") {
                snippets.search = snippet.title
                ui.module = .snippets
            }
        }

        // Knowledge base
        let roles = knowledge.roles
        items += knowledge.quickSearch(terms: terms, limit: CommandPalette.perSource).map { hit in
            let id = roles.idColumn.map { hit.record.value($0) } ?? ""
            let title = roles.titleColumn.map { hit.record.value($0) } ?? ""
            return PaletteItem(id: "kb-\(hit.id)", icon: "books.vertical", title: [id, title].filter { !$0.isEmpty }.joined(separator: " — "),
                               subtitle: roles.scopeColumn.map { hit.record.value($0) } ?? "", group: "Knowledge base") {
                knowledge.show(recordID: hit.record.id, query: q)
            }
        }

        // Exploit-DB (asynchronous, filled by searchExploits)
        if exploitQuery == q { items += exploitItems }

        // Chef operations
        items += ChefCatalogue.all.filter { matches($0.name + " " + $0.category) }.prefix(CommandPalette.perSource).map { operation in
            PaletteItem(id: "chef-\(operation.id)", icon: "wand.and.stars", title: operation.name, subtitle: "Add to the Chef recipe", group: "Chef") {
                chef.add(operation)
                ui.module = .chef
            }
        }

        // Activity log
        items += log.entries.reversed().filter { matches($0.text + " " + $0.source) }.prefix(CommandPalette.perSource).map { entry in
            PaletteItem(id: "log-\(entry.id)", icon: entry.kind.symbol, title: entry.text,
                        subtitle: "\(entry.kind.label) · \(entry.source)", group: "Log") {
                log.search = q
                ui.module = .activity
            }
        }
        return items
    }

    private func searchExploits(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, exploits.hasDatabase else {
            exploitItems = []
            exploitQuery = trimmed
            return
        }
        let terms = self.terms
        exploits.quickSearch(terms: terms, limit: CommandPalette.perSource) { hits in
            exploitQuery = trimmed
            exploitItems = hits.map { hit in
                PaletteItem(id: "edb-\(hit.id)", icon: "ladybug", title: hit.entry.title,
                            subtitle: "EDB-\(hit.entry.id) · \(hit.entry.date) · \(hit.entry.platform)/\(hit.entry.type)", group: "Exploit-DB") {
                    exploits.show(entryID: hit.entry.id, query: trimmed)
                }
            }
        }
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool
    @Environment(\.luikTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .frame(width: 18)
                .foregroundStyle(isSelected ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isSelected {
                Text("↩")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? theme.accentColor.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
    }
}
