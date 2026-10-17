import AppKit
import Foundation
import Observation
import SwiftUI

/// The plans of the engagement (plans.json in its folder) and the templates they are made from
/// (plan-templates.json, global). A template is what you refine after every engagement:
/// "Save as template" turns a worked plan back into one.
@Observable
final class PlanStore {
    static let shared = PlanStore()

    private static let fileName = "plans.json"
    private static let templatesFileName = "plan-templates.json"

    var plans: [Plan] = []
    var selectedPlanID: UUID?
    var selectedPhaseID: UUID?
    /// Your own templates; built-in ones are in PlanTemplate.builtIn.
    var customTemplates: [PlanTemplate] = []
    var showTemplateEditor = false
    var showNewPlan = false
    var lastError: String?
    @ObservationIgnored private var saver = Debouncer()
    @ObservationIgnored private var templateSaver = Debouncer()

    init() {
        customTemplates = Storage.load([PlanTemplate].self, from: PlanStore.templatesFileName) ?? []
        load()
    }

    var templates: [PlanTemplate] { customTemplates + PlanTemplate.builtIn }

    func template(id: UUID) -> PlanTemplate? {
        templates.first { $0.id == id }
    }

    // MARK: - Per engagement

    func reload() {
        saver.flush()
        load()
    }

    private func load() {
        plans = Storage.load([Plan].self, at: EngagementStore.shared.fileURL(PlanStore.fileName)) ?? []
        selectedPlanID = plans.first?.id
        selectedPhaseID = plans.first?.phases.first?.id
    }

    var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(PlanStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.plans, at: url)
        }
    }

    func flush() {
        saver.flush()
        templateSaver.flush()
    }

    // MARK: - Plans

    @discardableResult
    func createPlan(from template: PlanTemplate, name: String? = nil) -> Plan {
        var plan = template.instantiate(name: name)
        // Prefill from the engagement where the labels match.
        let engagement = EngagementStore.shared.current
        for index in plan.fields.indices {
            switch plan.fields[index].label.lowercased() {
            case "client": plan.fields[index].value = engagement.client
            case "reference": plan.fields[index].value = engagement.reference
            case "scope":
                var lines = engagement.scope
                if !engagement.exclusions.isEmpty { lines += ["", "Excluded:"] + engagement.exclusions }
                plan.fields[index].value = lines.joined(separator: "\n")
            default: break
            }
        }
        plans.append(plan)
        selectedPlanID = plan.id
        selectedPhaseID = plan.phases.first?.id
        scheduleSave()
        ActivityLog.shared.record(.action, "Plan “\(plan.name)” created from template “\(template.name)”", source: "Plan")
        return plan
    }

    func deletePlan(_ id: UUID) {
        plans.removeAll { $0.id == id }
        if selectedPlanID == id {
            selectedPlanID = plans.first?.id
            selectedPhaseID = plans.first?.phases.first?.id
        }
        scheduleSave()
    }

    func duplicatePlan(_ id: UUID) {
        guard let plan = plans.first(where: { $0.id == id }) else { return }
        var copy = PlanTemplate.from(plan, name: plan.name).instantiate(name: plan.name + " (copy)")
        copy.templateName = plan.templateName
        plans.append(copy)
        selectedPlanID = copy.id
        selectedPhaseID = copy.phases.first?.id
        scheduleSave()
    }

    /// Binding to one plan; every change is saved (debounced).
    func binding(for id: UUID) -> Binding<Plan> {
        Binding(
            get: { [weak self] in
                self?.plans.first { $0.id == id } ?? Plan(name: "")
            },
            set: { [weak self] newValue in
                guard let self, let index = self.plans.firstIndex(where: { $0.id == id }) else { return }
                self.plans[index] = newValue
                self.scheduleSave()
            }
        )
    }

    func setStatus(_ status: NodeStatus, item itemID: UUID, in planID: UUID) {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }) else { return }
        for phaseIndex in plans[planIndex].phases.indices {
            if let itemIndex = plans[planIndex].phases[phaseIndex].items.firstIndex(where: { $0.id == itemID }) {
                plans[planIndex].phases[phaseIndex].items[itemIndex].status = status
                scheduleSave()
                return
            }
        }
    }

    /// Every item not yet handled, across the plan (for the summary and ⌘K).
    func openItems(in plan: Plan) -> [(phase: PlanPhase, item: PlanItem)] {
        plan.phases.flatMap { phase in phase.items.filter { $0.status == .todo || $0.status == .inProgress }.map { (phase, $0) } }
    }

    // MARK: - Templates

    func saveTemplate(_ template: PlanTemplate) {
        var stored = template
        stored.builtIn = false
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = stored
        } else {
            customTemplates.insert(stored, at: 0)
        }
        scheduleTemplateSave()
    }

    func deleteTemplate(_ id: UUID) {
        customTemplates.removeAll { $0.id == id }
        scheduleTemplateSave()
    }

    /// A built-in template becomes an editable copy of your own.
    @discardableResult
    func duplicateTemplate(_ template: PlanTemplate, name: String? = nil) -> PlanTemplate {
        let copy = PlanTemplate(name: name ?? template.name + " (copy)", summary: template.summary,
                                fields: template.fields.map { $0.fresh() }, phases: template.phases.map { $0.fresh() })
        customTemplates.insert(copy, at: 0)
        scheduleTemplateSave()
        return copy
    }

    /// The structure of a worked plan as a new template (statuses, notes and answers dropped).
    @discardableResult
    func saveAsTemplate(_ plan: Plan, name: String) -> PlanTemplate {
        let template = PlanTemplate.from(plan, name: name)
        customTemplates.insert(template, at: 0)
        scheduleTemplateSave()
        ActivityLog.shared.record(.action, "Plan “\(plan.name)” saved as template “\(name)”", source: "Plan")
        return template
    }

    private func scheduleTemplateSave() {
        templateSaver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.customTemplates, to: PlanStore.templatesFileName)
        }
    }

    // MARK: - Export / import

    func exportTemplateJSON(_ template: PlanTemplate) -> Data? {
        var stored = template
        stored.builtIn = false
        return try? JSONEncoder.iso.encode(stored)
    }

    /// A template file (one template or an array); fresh ids so nothing collides.
    func importTemplates(from data: Data) throws -> Int {
        let decoder = JSONDecoder.iso
        var imported: [PlanTemplate] = []
        if let one = try? decoder.decode(PlanTemplate.self, from: data) {
            imported = [one]
        } else if let many = try? decoder.decode([PlanTemplate].self, from: data) {
            imported = many
        } else {
            throw NSError(domain: "Luik", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a plan template file (expected JSON exported by Luik)."])
        }
        for template in imported {
            let fresh = PlanTemplate(name: template.name, summary: template.summary, fields: template.fields.map { $0.fresh() }, phases: template.phases.map { $0.fresh() })
            customTemplates.insert(fresh, at: 0)
        }
        scheduleTemplateSave()
        return imported.count
    }

    /// The plan as Markdown for the report: fields, then every phase as a table.
    func markdown(for plan: Plan) -> String {
        var out = "# \(plan.name)\n\n"
        let engagement = EngagementStore.shared.current
        out += "_Engagement: \(engagement.displayName)"
        if !plan.templateName.isEmpty { out += " · template: \(plan.templateName)" }
        let progress = plan.progress
        out += " · \(progress.done) of \(progress.total) items done_\n\n"
        let filled = plan.fields.filter { !$0.value.isEmpty }
        if !filled.isEmpty {
            for field in filled {
                let value = field.kind == .toggle ? (field.value == "true" ? "Yes" : "No") : field.value
                if field.kind == .multiline && value.contains("\n") {
                    out += "**\(field.label)**\n\n\(value)\n\n"
                } else {
                    out += "**\(field.label)**: \(value)  \n"
                }
            }
            out += "\n"
        }
        for phase in plan.phases {
            let p = phase.progress
            out += "## \(phase.name) (\(p.done)/\(p.total))\n\n"
            if !phase.summary.isEmpty { out += "_\(phase.summary)_\n\n" }
            out += "| Status | Item | Notes |\n|---|---|---|\n"
            for item in phase.items {
                var notes = item.notes.replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "|", with: "\\|")
                let answers = item.fields.filter { !$0.value.isEmpty && !(($0.kind == .toggle) && $0.value != "true") }
                    .map { "\($0.label): \($0.kind == .toggle ? "yes" : $0.value)" }
                if !answers.isEmpty {
                    notes += (notes.isEmpty ? "" : "<br>") + answers.joined(separator: "<br>")
                }
                out += "| \(item.status.label) | \(item.title.replacingOccurrences(of: "|", with: "\\|")) | \(notes) |\n"
            }
            out += "\n"
        }
        return out
    }

    func copyMarkdown(_ plan: Plan) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: plan), forType: .string)
    }
}
