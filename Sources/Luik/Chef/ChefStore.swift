import AppKit
import Foundation
import Observation

/// One step in the recipe: an operation plus its parameter values.
struct ChefStep: Identifiable, Codable, Equatable {
    var id = UUID()
    var operationID: String
    var values: [String: String] = [:]
    var enabled = true
}

/// A saved recipe.
struct ChefRecipe: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var steps: [ChefStep]
}

/// Result of running one step.
struct ChefStepResult: Identifiable {
    let id: UUID          // step id
    let error: String?
    let byteCount: Int
}

/// A "magic" suggestion: what the input looks like and the operation that decodes it.
struct ChefSuggestion: Identifiable {
    let id: String
    let title: String
    let operationID: String
    let preview: String
}

/// Input → recipe → output, recalculated on every change (like CyberChef's auto-bake).
@Observable
final class ChefStore {
    static let shared = ChefStore()

    private static let fileName = "chef.json"

    struct Persisted: Codable {
        var input: String
        var steps: [ChefStep]
        var recipes: [ChefRecipe]
    }

    var input: String = ""
    var steps: [ChefStep] = []
    var recipes: [ChefRecipe] = []
    var operationSearch: String = ""

    private(set) var output: Data = Data()
    private(set) var stepResults: [ChefStepResult] = []
    private(set) var suggestions: [ChefSuggestion] = []

    @ObservationIgnored private var saver = Debouncer(delay: 1.0)

    init() {
        if let persisted = Storage.load(Persisted.self, from: ChefStore.fileName) {
            input = persisted.input
            steps = persisted.steps
            recipes = persisted.recipes
        }
        bake()
    }

    var outputText: String {
        String(decoding: output, as: UTF8.self)
    }

    var outputIsBinary: Bool {
        output.contains { $0 < 9 || ($0 > 13 && $0 < 32) }
    }

    var filteredOperations: [ChefOperation] {
        let query = operationSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return ChefCatalogue.all }
        return ChefCatalogue.all.filter { $0.name.lowercased().contains(query) || $0.category.lowercased().contains(query) }
    }

    // MARK: - Recipe editing

    func add(_ operation: ChefOperation) {
        var values: [String: String] = [:]
        for param in operation.params { values[param.id] = param.defaultValue }
        steps.append(ChefStep(operationID: operation.id, values: values))
        bake()
    }

    func remove(_ step: ChefStep) {
        steps.removeAll { $0.id == step.id }
        bake()
    }

    func move(_ step: ChefStep, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        let target = index + offset
        guard target >= 0, target < steps.count else { return }
        steps.swapAt(index, target)
        bake()
    }

    func clearRecipe() {
        steps.removeAll()
        bake()
    }

    func setValue(_ value: String, for key: String, in step: ChefStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].values[key] = value
        bake()
    }

    func toggle(_ step: ChefStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].enabled.toggle()
        bake()
    }

    func value(_ key: String, in step: ChefStep) -> String {
        if let value = step.values[key] { return value }
        return ChefCatalogue.operation(step.operationID)?.params.first { $0.id == key }?.defaultValue ?? ""
    }

    // MARK: - Running

    func bake() {
        var data = Data(input.utf8)
        var results: [ChefStepResult] = []
        var failed = false
        for step in steps {
            guard step.enabled, !failed else {
                results.append(ChefStepResult(id: step.id, error: nil, byteCount: data.count))
                continue
            }
            guard let operation = ChefCatalogue.operation(step.operationID) else {
                results.append(ChefStepResult(id: step.id, error: "Unknown operation.", byteCount: data.count))
                continue
            }
            do {
                data = try operation.run(data, step.values)
                results.append(ChefStepResult(id: step.id, error: nil, byteCount: data.count))
            } catch {
                results.append(ChefStepResult(id: step.id, error: error.localizedDescription, byteCount: data.count))
                failed = true
            }
        }
        output = data
        stepResults = results
        suggestions = ChefStore.detect(input)
        scheduleSave()
    }

    func result(for step: ChefStep) -> ChefStepResult? {
        stepResults.first { $0.id == step.id }
    }

    /// Looks at the input and proposes decodings that produce readable text.
    private static func detect(_ input: String) -> [ChefSuggestion] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var found: [ChefSuggestion] = []

        func readable(_ data: Data) -> String? {
            guard !data.isEmpty else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            let printable = text.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" || $0 == "\r" }.count
            guard text.unicodeScalars.count > 0, Double(printable) / Double(text.unicodeScalars.count) > 0.9, !text.contains("\u{FFFD}") else { return nil }
            return String(text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        }

        if trimmed.split(separator: ".").count == 3, trimmed.hasPrefix("ey") {
            found.append(ChefSuggestion(id: "jwt", title: "Looks like a JWT", operationID: "jwt-decode", preview: "header + payload as JSON"))
        }
        if Hex.looksLikeHex(trimmed), let data = Hex.decode(trimmed), let preview = readable(data) {
            found.append(ChefSuggestion(id: "hex", title: "Looks like hex", operationID: "from-hex", preview: preview))
        }
        if Base64.looksLikeBase64(trimmed), let data = Base64.decodeLenient(trimmed) {
            if Gzip.looksLikeGzip(data) {
                found.append(ChefSuggestion(id: "b64gz", title: "Looks like Base64 of gzip data", operationID: "from-base64", preview: "add Gunzip after From Base64"))
            } else if let preview = readable(data) {
                found.append(ChefSuggestion(id: "b64", title: "Looks like Base64", operationID: "from-base64", preview: preview))
            }
        }
        if trimmed.contains("%"), let decoded = trimmed.removingPercentEncoding, decoded != trimmed {
            found.append(ChefSuggestion(id: "url", title: "Looks URL-encoded", operationID: "url-decode", preview: String(decoded.prefix(80))))
        }
        if trimmed.contains("&") && trimmed.contains(";"), HTMLEntities.decode(trimmed) != trimmed {
            found.append(ChefSuggestion(id: "html", title: "Contains HTML entities", operationID: "html-decode", preview: String(HTMLEntities.decode(trimmed).prefix(80))))
        }
        if trimmed.contains("\\u"), let unescape = ChefCatalogue.operation("unicode-unescape"),
           let data = try? unescape.run(Data(trimmed.utf8), [:]), let preview = readable(data), preview != String(trimmed.prefix(80)) {
            found.append(ChefSuggestion(id: "uni", title: "Contains \\u escapes", operationID: "unicode-unescape", preview: preview))
        }
        if !trimmed.contains("\n") {
            if trimmed.hasPrefix("$9$"), let decoded = JuniperSecret.decode(trimmed) {
                found.append(ChefSuggestion(id: "juniper", title: "Looks like a Juniper $9$ secret", operationID: "juniper9-decode", preview: decoded))
            } else if trimmed.count >= 4, trimmed.count <= 100, ![32, 40, 64, 128].contains(trimmed.count), let decoded = CiscoType7.decode(trimmed) {
                found.append(ChefSuggestion(id: "cisco7", title: "Looks like a Cisco type 7 password", operationID: "cisco7-decode", preview: decoded))
            }
            let analysis = HashIdentifier.analyze(trimmed)
            if !analysis.isEmpty, !(Double(trimmed) != nil && trimmed.count < 20) {
                let names = (analysis.likely.isEmpty ? analysis.candidates : analysis.likely).prefix(3).map { $0.name }
                found.append(ChefSuggestion(id: "hash", title: "Looks like a hash", operationID: "identify-hash",
                                            preview: names.joined(separator: " / ")))
            }
        }
        if let number = Double(trimmed), number > 1_000_000_000, number < 1e16 {
            found.append(ChefSuggestion(id: "unix", title: "Looks like a Unix timestamp", operationID: "from-unix", preview: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number))))
        }
        if let data = trimmed.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil, !trimmed.contains("\n  ") {
            found.append(ChefSuggestion(id: "json", title: "Looks like JSON", operationID: "json-pretty", preview: "beautify"))
        }
        if trimmed.allSatisfy({ $0 == "0" || $0 == "1" || $0.isWhitespace }), trimmed.filter({ !$0.isWhitespace }).count % 8 == 0, trimmed.count >= 16 {
            found.append(ChefSuggestion(id: "bin", title: "Looks like binary", operationID: "from-binary", preview: "8 bits per byte"))
        }
        return found
    }

    // MARK: - Input / output helpers

    func useOutputAsInput() {
        input = outputText
        steps.removeAll()
        bake()
    }

    func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
    }

    func pasteAsInput() {
        if let text = NSPasteboard.general.string(forType: .string) {
            input = text
            bake()
        }
    }

    // MARK: - Saved recipes

    func saveRecipe(named name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, !steps.isEmpty else { return }
        if let index = recipes.firstIndex(where: { $0.name == cleaned }) {
            recipes[index].steps = steps
        } else {
            recipes.append(ChefRecipe(name: cleaned, steps: steps))
        }
        scheduleSave()
    }

    func load(_ recipe: ChefRecipe) {
        steps = recipe.steps.map { step in
            var copy = step
            copy.id = UUID()
            return copy
        }
        bake()
    }

    func deleteRecipe(_ recipe: ChefRecipe) {
        recipes.removeAll { $0.id == recipe.id }
        scheduleSave()
    }

    /// The recipe as a readable line, e.g. for notes: "From Base64 → Gunzip → JSON Beautify".
    var recipeDescription: String {
        steps.filter { $0.enabled }.compactMap { ChefCatalogue.operation($0.operationID)?.name }.joined(separator: " → ")
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(Persisted(input: self.input, steps: self.steps, recipes: self.recipes), to: ChefStore.fileName)
        }
    }

    func flush() {
        saver.flush()
    }
}
