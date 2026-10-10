import AppKit
import SwiftUI

/// CyberChef-style tab: operations on the left, the recipe in the middle, input and output on the right.
struct ChefView: View {
    @Environment(ChefStore.self) private var store
    @State private var showSaveRecipe = false
    @State private var recipeName = ""

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            operationsPane
                .frame(width: 230)
            Divider()
            recipePane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            Divider()
            ioPane
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSaveRecipe) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save recipe")
                    .font(.headline)
                Text(store.recipeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $recipeName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveRecipe)
                HStack {
                    Spacer()
                    Button("Cancel") { showSaveRecipe = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Save", action: saveRecipe)
                        .keyboardShortcut(.defaultAction)
                        .disabled(recipeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
            .frame(width: 360)
        }
    }

    private func saveRecipe() {
        store.saveRecipe(named: recipeName)
        showSaveRecipe = false
        recipeName = ""
    }

    // MARK: Operations

    private var operationsPane: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            TextField("Find operation…", text: $store.operationSearch)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List {
                ForEach(ChefCatalogue.categories, id: \.self) { category in
                    let operations = store.filteredOperations.filter { $0.category == category }
                    if !operations.isEmpty {
                        Section(category) {
                            ForEach(operations) { operation in
                                HStack {
                                    Text(operation.name)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { store.add(operation) }
                                .help("Add to the recipe")
                            }
                        }
                    }
                }
                if !store.recipes.isEmpty {
                    Section("Saved recipes") {
                        ForEach(store.recipes) { recipe in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name)
                                    Text(recipe.steps.compactMap { ChefCatalogue.operation($0.operationID)?.name }.joined(separator: " → "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { store.load(recipe) }
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.deleteRecipe(recipe) }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Recipe

    private var recipePane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recipe")
                    .font(.headline)
                Spacer()
                Button {
                    recipeName = ""
                    showSaveRecipe = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(store.steps.isEmpty)
                .help("Save this recipe")
                Button {
                    store.clearRecipe()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(store.steps.isEmpty)
                .help("Clear the recipe")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if store.steps.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Click operations on the left to build a recipe.\nThe output updates as you type.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(store.steps.enumerated()), id: \.element.id) { index, step in
                            StepCard(step: step, index: index, count: store.steps.count)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    // MARK: Input / output

    private var ioPane: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            HStack {
                Text("Input")
                    .font(.headline)
                Text("\(store.input.utf8.count) bytes")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Paste") { store.pasteAsInput() }
                Button("Clear") {
                    store.input = ""
                    store.bake()
                }
                .disabled(store.input.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            TextEditor(text: $store.input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .onChange(of: store.input) { _, _ in store.bake() }

            if !store.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.secondary)
                        ForEach(store.suggestions) { suggestion in
                            Button {
                                if let operation = ChefCatalogue.operation(suggestion.operationID) {
                                    store.add(operation)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.title)
                                        .font(.caption.weight(.semibold))
                                    Text(suggestion.preview)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .help("Add \(ChefCatalogue.operation(suggestion.operationID)?.name ?? "") to the recipe")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            HStack {
                Text("Output")
                    .font(.headline)
                Text("\(store.output.count) bytes" + (store.outputIsBinary ? " · binary (add To Hex or To Base64 to view)" : ""))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.useOutputAsInput()
                } label: {
                    Label("Use as input", systemImage: "arrow.uturn.up")
                }
                .disabled(store.output.isEmpty)
                .help("Move the output to the input and start a new recipe")
                Button {
                    store.copyOutput()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.output.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            ScrollView {
                Text(store.outputText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .bottom], 12)
        }
    }
}

/// One step of the recipe with its parameter editors and result/error line.
struct StepCard: View {
    let step: ChefStep
    let index: Int
    let count: Int
    @Environment(ChefStore.self) private var store

    var body: some View {
        let operation = ChefCatalogue.operation(step.operationID)
        let result = store.result(for: step)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(get: { step.enabled }, set: { _ in store.toggle(step) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(step.enabled ? "Disable this step" : "Enable this step")
                Text("\(index + 1). \(operation?.name ?? step.operationID)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(step.enabled ? .primary : .secondary)
                Spacer()
                Button { store.move(step, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                Button { store.move(step, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
                    .disabled(index == count - 1)
                Button { store.remove(step) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if let operation {
                ForEach(operation.params) { param in
                    ParamEditor(param: param, step: step)
                }
            }
            if let result {
                if let error = result.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if step.enabled {
                    Text("→ \(result.byteCount) bytes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(step.enabled ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Editor for one parameter of a step.
struct ParamEditor: View {
    let param: ChefParam
    let step: ChefStep
    @Environment(ChefStore.self) private var store

    var body: some View {
        let binding = Binding<String>(
            get: { store.value(param.id, in: step) },
            set: { store.setValue($0, for: param.id, in: step) }
        )
        switch param.kind {
        case .text:
            LabeledContent(param.label) {
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }
        case .number:
            LabeledContent(param.label) {
                TextField("", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
        case .choice(let options):
            LabeledContent(param.label) {
                Picker("", selection: binding) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
            }
        case .toggle:
            Toggle(param.label, isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = $0 ? "true" : "false" }))
                .toggleStyle(.checkbox)
        }
    }
}
