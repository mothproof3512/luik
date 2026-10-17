import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Plan tab: the engagement's test plans (from templates) with phases, items to tick off,
/// notes and fill-in fields; Markdown export for the report; the plan can become a template.
struct PlanView: View {
    @Environment(PlanStore.self) private var store
    @Environment(EngagementStore.self) private var engagements
    @Environment(\.luikTheme) private var theme
    @State private var templateNameForSave = ""
    @State private var showSaveAsTemplate = false
    @State private var deletingPlan: Plan?

    var body: some View {
        @Bindable var store = store
        SplitPane(storageKey: "planSplitFraction", defaultFraction: 0.26, minFraction: 0.16, maxFraction: 0.45) {
            sidebar
        } trailing: {
            detail
        }
        .sheet(isPresented: $store.showNewPlan) {
            NewPlanSheet()
        }
        .sheet(isPresented: $store.showTemplateEditor) {
            PlanTemplateEditor()
        }
        .alert("Save this plan as a template", isPresented: $showSaveAsTemplate) {
            TextField("Template name", text: $templateNameForSave)
            Button("Save") {
                if let plan = store.selectedPlan, !templateNameForSave.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.saveAsTemplate(plan, name: templateNameForSave.trimmingCharacters(in: .whitespaces))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The phases, items, hints and field definitions are kept; statuses, notes and answers are not. The template is yours to refine for the next engagement.")
        }
        .confirmationDialog("Delete the plan “\(deletingPlan?.name ?? "")”?", isPresented: Binding(get: { deletingPlan != nil }, set: { if !$0 { deletingPlan = nil } })) {
            Button("Delete", role: .destructive) {
                if let plan = deletingPlan { store.deletePlan(plan.id) }
                deletingPlan = nil
            }
        } message: {
            Text("Statuses, notes and answers of this plan are lost. Export it as Markdown first if you need them.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Plans — \(engagements.current.displayName)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    store.showNewPlan = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New plan from a template")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if store.plans.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No plan yet for this engagement.")
                        .font(.callout)
                    Text("A plan is the engagement-level checklist: phases with items to work through, notes and fill-in fields, exported as Markdown for the report. Start from a template — external, internal/AD, web application or minimal — and shape it; afterwards save the worked plan as your own template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.showNewPlan = true
                    } label: {
                        Label("New plan from template…", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Templates…") { store.showTemplateEditor = true }
                        .font(.caption)
                }
                .padding(12)
                Spacer()
            } else {
                List(selection: $store.selectedPhaseID) {
                    ForEach(store.plans) { plan in
                        Section {
                            ForEach(plan.phases) { phase in
                                let p = phase.progress
                                HStack(spacing: 6) {
                                    Image(systemName: p.total > 0 && p.done == p.total ? "checkmark.circle.fill" : (p.done > 0 ? "circle.lefthalf.filled" : "circle"))
                                        .foregroundStyle(p.total > 0 && p.done == p.total ? Color.green : (p.done > 0 ? Color.orange : Color.secondary))
                                        .font(.caption)
                                    Text(phase.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(p.done)/\(p.total)")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .tag(phase.id)
                            }
                        } header: {
                            let p = plan.progress
                            HStack(spacing: 6) {
                                Image(systemName: "list.clipboard")
                                    .foregroundStyle(theme.accentColor)
                                Text(plan.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(p.done)/\(p.total)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedPlanID = plan.id
                                store.selectedPhaseID = plan.phases.first?.id
                            }
                            .contextMenu {
                                Button("Copy as Markdown") { store.copyMarkdown(plan) }
                                Button("Export as Markdown…") { exportMarkdown(plan) }
                                Button("Save as template…") {
                                    store.selectedPlanID = plan.id
                                    templateNameForSave = plan.name
                                    showSaveAsTemplate = true
                                }
                                Button("Duplicate") { store.duplicatePlan(plan.id) }
                                Divider()
                                Button("Delete plan…", role: .destructive) { deletingPlan = plan }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: store.selectedPhaseID) { _, phaseID in
                    if let phaseID, let plan = store.plans.first(where: { $0.phases.contains { $0.id == phaseID } }) {
                        store.selectedPlanID = plan.id
                    }
                }
                HStack {
                    Menu {
                        Button("Templates…") { store.showTemplateEditor = true }
                        Divider()
                        if let plan = store.selectedPlan {
                            Button("Copy plan as Markdown") { store.copyMarkdown(plan) }
                            Button("Export plan as Markdown…") { exportMarkdown(plan) }
                            Button("Save plan as template…") {
                                templateNameForSave = plan.name
                                showSaveAsTemplate = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private func exportMarkdown(_ plan: Plan) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = plan.name.lowercased().replacingOccurrences(of: " ", with: "-") + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.markdown(for: plan).write(to: url, atomically: true, encoding: .utf8)
            ActivityLog.shared.record(.action, "Plan “\(plan.name)” exported to \(url.path)", source: "Plan")
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let planID = store.selectedPlanID, store.plans.contains(where: { $0.id == planID }) {
            PlanDetailView(plan: store.binding(for: planID), phaseID: store.selectedPhaseID)
                .id(planID)
        } else {
            VStack {
                Spacer()
                Text(store.plans.isEmpty ? "Create a plan from a template with +." : "Select a phase in the sidebar.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One plan: its fields, then the selected phase with its items.
struct PlanDetailView: View {
    @Binding var plan: Plan
    let phaseID: UUID?
    @Environment(\.luikTheme) private var theme
    @AppStorage("planFieldsExpanded") private var fieldsExpanded = true
    @State private var expandedItems: Set<UUID> = []

    private var phaseIndex: Int? {
        plan.phases.firstIndex { $0.id == phaseID } ?? (plan.phases.isEmpty ? nil : 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("Plan name", text: $plan.name)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                    if !plan.templateName.isEmpty {
                        Text("from “\(plan.templateName)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                let progress = plan.progress
                if progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                        Text("\(progress.done) of \(progress.total) items done across \(plan.phases.count) phases")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !plan.fields.isEmpty {
                    DisclosureGroup(isExpanded: $fieldsExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach($plan.fields) { $field in
                                PlanFieldEditor(field: $field)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        let filled = plan.fields.filter { $0.isFilled }.count
                        Text("Engagement details (\(filled)/\(plan.fields.count) filled)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }

                if let index = phaseIndex {
                    phaseView(index: index)
                } else {
                    Text("This plan has no phases yet — add one from the Templates editor, or save a plan with phases as a template.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func phaseView(index: Int) -> some View {
        let phase = plan.phases[index]
        let progress = phase.progress
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Phase", text: $plan.phases[index].name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Mark all items done") { setAll(.done, index: index) }
                    Button("Mark all items to do") { setAll(.todo, index: index) }
                    Divider()
                    Button("Expand all") { expandedItems.formUnion(phase.items.map { $0.id }) }
                    Button("Collapse all") { expandedItems.subtract(phase.items.map { $0.id }) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextField("What this phase is about (optional)", text: $plan.phases[index].summary)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(plan.phases[index].items) { item in
                if let itemIndex = plan.phases[index].items.firstIndex(where: { $0.id == item.id }) {
                    itemRow(phaseIndex: index, itemIndex: itemIndex)
                }
            }
            Button {
                let item = PlanItem(title: "New item")
                plan.phases[index].items.append(item)
                expandedItems.insert(item.id)
            } label: {
                Label("Add item", systemImage: "plus")
            }
            .buttonStyle(.link)
        }
    }

    private func setAll(_ status: NodeStatus, index: Int) {
        for itemIndex in plan.phases[index].items.indices where plan.phases[index].items[itemIndex].status != .notApplicable || status == .todo {
            plan.phases[index].items[itemIndex].status = status
        }
    }

    private func itemRow(phaseIndex: Int, itemIndex: Int) -> some View {
        let item = plan.phases[phaseIndex].items[itemIndex]
        let expanded = expandedItems.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    plan.phases[phaseIndex].items[itemIndex].status = item.status.next
                } label: {
                    Image(systemName: item.status.symbol)
                        .foregroundStyle(item.status.color)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("\(item.status.label) — click to cycle: to do → in progress → done → N/A")
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Item", text: $plan.phases[phaseIndex].items[itemIndex].title)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .opacity(item.status == .notApplicable ? 0.5 : 1)
                    if !item.hint.isEmpty && !expanded {
                        Text(item.hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !item.notes.isEmpty && !expanded {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                        .help(item.notes)
                }
                let answered = item.fields.filter { $0.isFilled }.count
                if !item.fields.isEmpty {
                    Text("\(answered)/\(item.fields.count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(answered == item.fields.count ? Color.green : Color.secondary)
                        .help("Fields filled in")
                }
                Button {
                    if expanded { expandedItems.remove(item.id) } else { expandedItems.insert(item.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .contextMenu {
                ForEach(NodeStatus.allCases, id: \.self) { status in
                    Button(status.label) { plan.phases[phaseIndex].items[itemIndex].status = status }
                }
                Divider()
                Button("Move up") { move(phaseIndex: phaseIndex, itemIndex: itemIndex, by: -1) }
                    .disabled(itemIndex == 0)
                Button("Move down") { move(phaseIndex: phaseIndex, itemIndex: itemIndex, by: 1) }
                    .disabled(itemIndex == plan.phases[phaseIndex].items.count - 1)
                Divider()
                Button("Delete item", role: .destructive) {
                    expandedItems.remove(item.id)
                    plan.phases[phaseIndex].items.remove(at: itemIndex)
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("How to approach this (hint from the template)", text: $plan.phases[phaseIndex].items[itemIndex].hint, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach($plan.phases[phaseIndex].items[itemIndex].fields) { $field in
                        PlanFieldEditor(field: $field)
                    }
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $plan.phases[phaseIndex].items[itemIndex].notes)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.leading, 30)
            }
        }
        .padding(8)
        .background(Color.white.opacity(item.status == .done ? 0.03 : 0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func move(phaseIndex: Int, itemIndex: Int, by offset: Int) {
        let target = itemIndex + offset
        guard plan.phases[phaseIndex].items.indices.contains(target) else { return }
        plan.phases[phaseIndex].items.swapAt(itemIndex, target)
    }
}

/// A fill-in field with the control for its kind.
struct PlanFieldEditor: View {
    @Binding var field: PlanField

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(field.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
                .padding(.top, field.kind == .multiline ? 6 : 3)
            switch field.kind {
            case .text:
                TextField("", text: $field.value)
                    .textFieldStyle(.roundedBorder)
            case .multiline:
                TextEditor(text: $field.value)
                    .font(.callout)
                    .frame(minHeight: 48, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            case .date:
                HStack(spacing: 6) {
                    TextField("yyyy-mm-dd", text: $field.value)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    Button("Today") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        field.value = formatter.string(from: Date())
                    }
                    .font(.caption)
                }
            case .choice:
                Picker("", selection: $field.value) {
                    Text("—").tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
            case .toggle:
                Toggle("", isOn: Binding(get: { field.value == "true" }, set: { field.value = $0 ? "true" : "false" }))
                    .labelsHidden()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Choose a template and a name for a new plan.
struct NewPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanStore.self) private var store
    @Environment(\.luikTheme) private var theme
    @State private var selectedTemplateID: UUID?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New plan")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    if let template = selectedTemplateID.flatMap({ store.template(id: $0) }) {
                        store.createPlan(from: template, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedTemplateID == nil)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                List(selection: $selectedTemplateID) {
                    if !store.customTemplates.isEmpty {
                        Section("Your templates") {
                            ForEach(store.customTemplates) { template in
                                templateRow(template)
                            }
                        }
                    }
                    Section("Built in") {
                        ForEach(PlanTemplate.builtIn) { template in
                            templateRow(template)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(width: 280)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let template = selectedTemplateID.flatMap({ store.template(id: $0) }) {
                        Text(template.name)
                            .font(.title3.weight(.semibold))
                        if !template.summary.isEmpty {
                            Text(template.summary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        TextField("Plan name (optional — defaults to the template name)", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("\(template.phases.count) phases · \(template.itemCount) items · \(template.fields.count) fields")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(template.phases) { phase in
                                    Text(phase.name)
                                        .font(.callout.weight(.semibold))
                                    ForEach(phase.items) { item in
                                        Text("• \(item.title)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Spacer()
                        Text("Choose a template.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            if selectedTemplateID == nil {
                selectedTemplateID = store.templates.first?.id
            }
        }
    }

    private func templateRow(_ template: PlanTemplate) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(template.name)
                .lineLimit(1)
            Text("\(template.phases.count) phases · \(template.itemCount) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .tag(template.id)
    }
}
