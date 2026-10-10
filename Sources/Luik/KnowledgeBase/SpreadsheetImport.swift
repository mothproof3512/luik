import Foundation

enum ImportError: LocalizedError {
    case unreadable
    case unzipFailed(String)
    case noTables
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file could not be read."
        case .unzipFailed(let detail): return "The .xlsx could not be unpacked: \(detail)"
        case .noTables: return "No table with a header row and data rows was found."
        case .unsupported(let ext): return "Unsupported file type: .\(ext). Use .xlsx, .csv, .tsv or .json."
        }
    }
}

/// Reads .xlsx, .csv/.tsv and .json files into tables. No third-party code: an .xlsx is a zip
/// with XML inside, which is unpacked with the system's unzip and parsed with XMLParser.
enum SpreadsheetImport {
    static func importFile(at url: URL) throws -> [KBTable] {
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm":
            return try importXLSX(at: url)
        case "csv", "tsv", "txt":
            return try importCSV(at: url)
        case "json":
            return try importJSON(at: url)
        default:
            throw ImportError.unsupported(url.pathExtension)
        }
    }

    // MARK: - Shared: rows → table

    /// The header is the first row with at least two non-empty cells; everything after it is data.
    static func makeTable(name: String, rows: [[String]]) -> KBTable? {
        guard let headerIndex = rows.firstIndex(where: { row in row.filter { !$0.isEmpty }.count >= 2 }) else {
            return nil
        }
        let rawHeader = rows[headerIndex]
        let width = max(rawHeader.count, rows[headerIndex...].map { $0.count }.max() ?? 0)
        var columns: [String] = []
        var seen: Set<String> = []
        for index in 0..<width {
            var name = index < rawHeader.count ? rawHeader[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if name.isEmpty { name = "Column \(index + 1)" }
            var unique = name
            var counter = 2
            while seen.contains(unique) {
                unique = "\(name) (\(counter))"
                counter += 1
            }
            seen.insert(unique)
            columns.append(unique)
        }

        var records: [KBRecord] = []
        for row in rows[(headerIndex + 1)...] {
            var values: [String: String] = [:]
            for (index, column) in columns.enumerated() where index < row.count {
                let cell = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !cell.isEmpty {
                    values[column] = cell
                }
            }
            if !values.isEmpty {
                records.append(KBRecord(values: values))
            }
        }
        guard !records.isEmpty else { return nil }
        // Drop columns that are empty in every record.
        let used = columns.filter { column in records.contains { $0.values[column] != nil } }
        return KBTable(name: name, columns: used, records: records)
    }

    // MARK: - XLSX

    static func importXLSX(at url: URL) throws -> [KBTable] {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("luik-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        try unzip(url, to: workDir)

        let sharedStrings = parseSharedStrings(at: workDir.appendingPathComponent("xl/sharedStrings.xml"))
        let sheets = parseWorkbook(at: workDir)
        guard !sheets.isEmpty else { throw ImportError.noTables }

        var tables: [KBTable] = []
        for sheet in sheets {
            let sheetURL = workDir.appendingPathComponent(sheet.path)
            guard let data = try? Data(contentsOf: sheetURL) else { continue }
            let rows = parseSheet(data: data, sharedStrings: sharedStrings)
            if let table = makeTable(name: sheet.name, rows: rows) {
                tables.append(table)
            }
        }
        guard !tables.isEmpty else { throw ImportError.noTables }
        return tables
    }

    private static func unzip(_ url: URL, to directory: URL) throws {
        let candidates: [(String, [String])] = [
            ("/usr/bin/unzip", ["-o", "-q", url.path, "-d", directory.path]),
            ("/usr/bin/ditto", ["-x", "-k", url.path, directory.path]),
        ]
        var lastError = "no unzip tool found"
        for (tool, arguments) in candidates where FileManager.default.isExecutableFile(atPath: tool) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                lastError = error.localizedDescription
                continue
            }
            if process.terminationStatus == 0,
               FileManager.default.fileExists(atPath: directory.appendingPathComponent("xl/workbook.xml").path) {
                return
            }
            let output = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            lastError = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "exit code \(process.terminationStatus)" : output
        }
        throw ImportError.unzipFailed(lastError)
    }

    private struct SheetRef {
        let name: String
        let path: String   // relative to the unzip root, e.g. "xl/worksheets/sheet1.xml"
    }

    /// Sheet names in workbook order, resolved to their XML paths through the relationships file.
    private static func parseWorkbook(at root: URL) -> [SheetRef] {
        guard let workbookData = try? Data(contentsOf: root.appendingPathComponent("xl/workbook.xml")) else { return [] }
        let relsData = try? Data(contentsOf: root.appendingPathComponent("xl/_rels/workbook.xml.rels"))

        let rels = AttributeCollector(element: "Relationship", keys: ["Id", "Target"])
        if let relsData {
            let parser = XMLParser(data: relsData)
            parser.delegate = rels
            parser.parse()
        }
        var targets: [String: String] = [:]
        for entry in rels.entries {
            if let id = entry["Id"], let target = entry["Target"] {
                targets[id] = target
            }
        }

        let sheets = AttributeCollector(element: "sheet", keys: ["name", "r:id", "sheetId"])
        let parser = XMLParser(data: workbookData)
        parser.shouldProcessNamespaces = false
        parser.delegate = sheets
        parser.parse()

        var result: [SheetRef] = []
        for (index, entry) in sheets.entries.enumerated() {
            let name = entry["name"] ?? "Sheet \(index + 1)"
            var path: String
            if let rid = entry["r:id"], let target = targets[rid] {
                path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            } else {
                path = "xl/worksheets/sheet\(index + 1).xml"
            }
            result.append(SheetRef(name: name, path: path))
        }
        return result
    }

    private static func parseSharedStrings(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let delegate = SharedStringsDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    private static func parseSheet(data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    /// "AB12" → 28 (1-based column number). Returns nil when the reference has no column letters.
    static func columnIndex(fromCellReference reference: String) -> Int? {
        var index = 0
        var sawLetter = false
        for scalar in reference.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break } // A–Z
            index = index * 26 + Int(scalar.value - 64)
            sawLetter = true
        }
        return sawLetter ? index : nil
    }

    // MARK: - CSV / TSV

    static func importCSV(at url: URL) throws -> [KBTable] {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard !text.isEmpty else { throw ImportError.unreadable }
        let rows = parseCSV(text)
        guard let table = makeTable(name: url.deletingPathExtension().lastPathComponent, rows: rows) else {
            throw ImportError.noTables
        }
        return [table]
    }

    static func parseCSV(_ text: String) -> [[String]] {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let delimiter: Character = [(",", firstLine.filter { $0 == "," }.count),
                                    (";", firstLine.filter { $0 == ";" }.count),
                                    ("\t", firstLine.filter { $0 == "\t" }.count)]
            .max { $0.1 < $1.1 }?.0 ?? ","

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let char = next() {
            if inQuotes {
                if char == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r", let following = next(), following != "\n" {
                    pending = following
                }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: - JSON

    static func importJSON(at url: URL) throws -> [KBTable] {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let object = try JSONSerialization.jsonObject(with: data)
        var tables: [KBTable] = []

        func table(named name: String, from array: [Any]) -> KBTable? {
            var columns: [String] = []
            var rows: [[String: String]] = []
            for element in array {
                guard let dict = element as? [String: Any] else { continue }
                var row: [String: String] = [:]
                for (key, value) in dict {
                    if !columns.contains(key) { columns.append(key) }
                    row[key] = stringify(value)
                }
                rows.append(row)
            }
            guard !rows.isEmpty else { return nil }
            let records = rows.map { KBRecord(values: $0.filter { !$0.value.isEmpty }) }
            return KBTable(name: name, columns: columns, records: records)
        }

        if let array = object as? [Any], let t = table(named: url.deletingPathExtension().lastPathComponent, from: array) {
            tables.append(t)
        } else if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if let array = value as? [Any], let t = table(named: key, from: array) {
                    tables.append(t)
                }
            }
        }
        guard !tables.isEmpty else { throw ImportError.noTables }
        return tables
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case is NSNull: return ""
        case let array as [Any]: return array.map(stringify).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.map { "\($0.key): \(stringify($0.value))" }.sorted().joined(separator: "; ")
        default: return String(describing: value)
        }
    }
}

// MARK: - XML delegates

/// Collects the attributes of every element with a given name.
private final class AttributeCollector: NSObject, XMLParserDelegate {
    let element: String
    let keys: [String]
    var entries: [[String: String]] = []

    init(element: String, keys: [String]) {
        self.element = element
        self.keys = keys
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == element || elementName.hasSuffix(":" + element) else { return }
        var entry: [String: String] = [:]
        for key in keys {
            if let value = attributeDict[key] {
                entry[key] = value
            }
        }
        entries.append(entry)
    }
}

/// sharedStrings.xml: every <si> becomes one string (rich-text runs are concatenated).
private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si":
            inItem = true
            current = ""
        case "t":
            inText = inItem
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText {
            current += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t":
            inText = false
        case "si":
            strings.append(current)
            inItem = false
        default:
            break
        }
    }
}

/// A worksheet: rows of cell strings, indexed by column position.
private final class SheetDelegate: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    var rows: [[String]] = []

    private var currentRow: [String] = []
    private var inRow = false
    private var cellType = ""
    private var cellColumn = 0
    private var nextColumn = 1
    private var collecting = false
    private var buffer = ""
    private var inInlineString = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            inRow = true
            currentRow = []
            nextColumn = 1
        case "c":
            cellType = attributeDict["t"] ?? ""
            if let reference = attributeDict["r"], let index = SpreadsheetImport.columnIndex(fromCellReference: reference) {
                cellColumn = index
            } else {
                cellColumn = nextColumn
            }
            nextColumn = cellColumn + 1
            buffer = ""
        case "v":
            collecting = inRow
        case "is":
            inInlineString = true
        case "t":
            collecting = inInlineString
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v", "t":
            collecting = false
        case "is":
            inInlineString = false
        case "c":
            let value = cellValue()
            if !value.isEmpty {
                while currentRow.count < cellColumn {
                    currentRow.append("")
                }
                currentRow[cellColumn - 1] = value
            }
            buffer = ""
            cellType = ""
        case "row":
            inRow = false
            rows.append(currentRow)
        default:
            break
        }
    }

    private func cellValue() -> String {
        switch cellType {
        case "s":
            if let index = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)), index >= 0, index < sharedStrings.count {
                return sharedStrings[index]
            }
            return ""
        case "b":
            return buffer.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "TRUE" : "FALSE"
        case "inlineStr", "str":
            return buffer
        default:
            // Number: show integers without a trailing ".0".
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(trimmed), double == double.rounded(), abs(double) < 1e15 {
                return String(Int64(double))
            }
            return trimmed
        }
    }
}
