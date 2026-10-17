import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Templates: your own are editable (name, summary, fields, phases, items with hints and item
/// fields); built-in ones are read-only until duplicated. Export / import as JSON to share them.
struct PlanTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanStore.self) private var store
    @Environment(\.luikTheme) private var theme
    @State private var selectedID: UUID?
    @State private var draft: PlanTemplate?
    @State private var status: String?
    @State private var deleting: PlanTemplate?

    private var selected: PlanTemplate? {
        selectedID.flatMap { store.template(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Plan templates")
                    .font(.headline)
                Spacer()
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Done") {
                    commitDraft()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 260)
                Divider()
                if let draft {
                    editor(Binding(get: { self.draft ?? draft }, set: { self.draft = $0 }), readOnly: draft.builtIn)
                } else {
                    VStack {
                        Spacer()
                        Text("Choose a template, or make a new one.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 980, height: 660)
        .onAppear {
            if selectedID == nil { selectedID = store.templates.first?.id }
            loadDraft()
        }
        .onChange(of: selectedID) { _, _ in
            commitDraft()
            loadDraft()
        }
        .onChange(of: draft) { _, _ in
            scheduleCommit()
        }
        .confirmationDialog("Delete the template “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let template = deleting {
                    store.deleteTemplate(template.id)
                    if selectedID == template.id { selectedID = store.templates.first?.id }
                }
                deleting = nil
            }
        } message: {
            Text("Plans already made from it are not affected.")
        }
    }

    private func loadDraft() {
        draft = selected
    }

    /// Edits are written to the store a moment after they stop (and when switching templates).
    @State private var commitWork: DispatchWorkItem?

    private func scheduleCommit() {
        commitWork?.cancel()
        let work = DispatchWorkItem { commitDraft() }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func commitDraft() {
        commitWork?.cancel()
        guard let draft, !draft.builtIn, let stored = store.template(id: draft.id), stored != draft else { return }
        store.saveTemplate(draft)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Your templates") {
                    if store.customTemplates.isEmpty {
                        Text("None yet — duplicate a built-in one, or save a plan as template.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.customTemplates) { template in
                        row(template)
                    }
                }
                Section("Built in") {
                    ForEach(PlanTemplate.builtIn) { template in
                        row(template)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 6) {
                Button {
                    commitDraft()
                    let template = PlanTemplate(name: "New template", fields: PlanTemplate.standardFields,
                                                phases: [PlanPhase(name: "Preparation", items: [PlanItem(title: "Scope confirmed")])])
                    store.saveTemplate(template)
                    selectedID = template.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("New template")
                Button {
                    if let selected {
                        commitDraft()
                        let copy = store.duplicateTemplate(selected)
                        selectedID = copy.id
                    }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selected == nil)
                .help("Duplicate (a built-in template becomes editable this way)")
                Button(role: .destructive) {
                    if let selected, !selected.builtIn { deleting = selected }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selected == nil || selected?.builtIn == true)
                .help("Delete this template")
                Spacer()
                Menu {
                    Button("Export this template as JSON…") { exportSelected() }
                        .disabled(selected == nil)
                    Button("Import templates from JSON…") { importTemplates() }
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Export / import")
            }
            .padding(8)
        }
    }

    private func row(_ template: PlanTemplate) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(template.name)
                .lineLimit(1)
            Text("\(template.phases.count) phases · \(template.itemCount) items · \(template.fields.count) fields")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .tag(template.id)
    }

    private func exportSelected() {
        guard let selected, let data = store.exportTemplateJSON(selected) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "luik-plan-" + selected.name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined() + ".json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            status = "Exported \(url.lastPathComponent)."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importTemplates() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var count = 0
        for url in panel.urls {
            do {
                count += try store.importTemplates(from: Data(contentsOf: url))
            } catch {
                status = "Import failed: \(error.localizedDescription)"
                return
            }
        }
        status = "Imported \(count) template(s)."
        selectedID = store.customTemplates.first?.id
    }

    // MARK: Editor

    private func editor(_ template: Binding<PlanTemplate>, readOnly: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if readOnly {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                        Text("Built-in template — duplicate it to make it your own.")
                            .font(.caption)
                        Button("Duplicate") {
                            let copy = store.duplicateTemplate(template.wrappedValue)
                            selectedID = copy.id
                        }
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                Group {
                TextField("Template name", text: template.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))
                TextField("What this template is for (optional)", text: template.summary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                section("Engagement details — fields filled in once per plan") {
                    ForEach(template.fields) { $field in
                        fieldDefinition($field, onDelete: { template.wrappedValue.fields.removeAll { $0.id == field.id } }, readOnly: readOnly)
                    }
                    if !readOnly {
                        Button {
                            template.wrappedValue.fields.append(PlanField(label: "New field"))
                        } label: {
                            Label("Add field", systemImage: "plus")
                        }
                        .buttonStyle(.link)
                    }
                }

                section("Phases and items") {
                    ForEach(template.phases) { $phase in
                        phaseEditor($phase, template: template, readOnly: readOnly)
                    }
                    if !readOnly {
                        Button {
                            template.wrappedValue.phases.append(PlanPhase(name: "New phase", items: [PlanItem(title: "New item")]))
                        } label: {
                            Label("Add phase", systemImage: "plus")
                        }
                        .buttonStyle(.link)
                    }
                }
                }
                .disabled(readOnly)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldDefinition(_ field: Binding<PlanField>, onDelete: @escaping () -> Void, readOnly: Bool) -> some View {
        HStack(spacing: 6) {
            TextField("Label", text: field.label)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Picker("", selection: field.kind) {
                ForEach(PlanField.Kind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            if field.wrappedValue.kind == .choice {
                TextField("Options, comma-separated", text: Binding(
                    get: { field.wrappedValue.options.joined(separator: ", ") },
                    set: { field.wrappedValue.options = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            if !readOnly {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func phaseEditor(_ phase: Binding<PlanPhase>, template: Binding<PlanTemplate>, readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Phase name", text: phase.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.weight(.semibold))
                if !readOnly {
                    let index = template.wrappedValue.phases.firstIndex { $0.id == phase.wrappedValue.id } ?? 0
                    Button { movePhase(template, from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                    Button { movePhase(template, from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain)
                        .disabled(index >= template.wrappedValue.phases.count - 1)
                    Button(role: .destructive) {
                        template.wrappedValue.phases.removeAll { $0.id == phase.wrappedValue.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            TextField("Summary (optional)", text: phase.summary)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            ForEach(phase.items) { $item in
                itemEditor($item, phase: phase, readOnly: readOnly)
            }
            if !readOnly {
                Button {
                    phase.wrappedValue.items.append(PlanItem(title: "New item"))
                } label: {
                    Label("Add item", systemImage: "plus")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func movePhase(_ template: Binding<PlanTemplate>, from index: Int, by offset: Int) {
        let target = index + offset
        guard template.wrappedValue.phases.indices.contains(index), template.wrappedValue.phases.indices.contains(target) else { return }
        template.wrappedValue.phases.swapAt(index, target)
    }

    private func itemEditor(_ item: Binding<PlanItem>, phase: Binding<PlanPhase>, readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Item", text: item.title)
                    .textFieldStyle(.roundedBorder)
                if !readOnly {
                    let index = phase.wrappedValue.items.firstIndex { $0.id == item.wrappedValue.id } ?? 0
                    Button { moveItem(phase, from: index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                    Button { moveItem(phase, from: index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain)
                        .disabled(index >= phase.wrappedValue.items.count - 1)
                    Button(role: .destructive) {
                        phase.wrappedValue.items.removeAll { $0.id == item.wrappedValue.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            TextField("Hint: how to approach it, what to look for (optional)", text: item.hint, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .padding(.leading, 20)
            ForEach(item.fields) { $field in
                fieldDefinition($field, onDelete: { item.wrappedValue.fields.removeAll { $0.id == field.id } }, readOnly: readOnly)
                    .padding(.leading, 20)
            }
            if !readOnly {
                Button {
                    item.wrappedValue.fields.append(PlanField(label: "Result", kind: .choice, options: ["Pass", "Fail", "Not tested"]))
                } label: {
                    Label("Add item field", systemImage: "plus")
                }
                .buttonStyle(.link)
                .font(.caption2)
                .padding(.leading, 20)
            }
        }
    }

    private func moveItem(_ phase: Binding<PlanPhase>, from index: Int, by offset: Int) {
        let target = index + offset
        guard phase.wrappedValue.items.indices.contains(index), phase.wrappedValue.items.indices.contains(target) else { return }
        phase.wrappedValue.items.swapAt(index, target)
    }
}
