import AppKit
import SwiftUI

/// Markdown rendered with Foundation's own parser: `AttributedString(markdown:)` with the full
/// syntax gives every block a presentation intent (header, paragraph, list item, code block,
/// block quote, table cell, thematic break); this view lays those blocks out. Inline marks (bold,
/// italic, code, links, strikethrough) are rendered by `Text` itself. No third-party code.
struct MarkdownView: View {
    let text: String
    /// Called for links that are not plain http(s) URLs (relative links to other documents).
    var onLink: ((URL) -> OpenURLAction.Result)?

    @Environment(\.luikTheme) private var theme
    @State private var elements: [MarkdownElement] = []
    @State private var parsedText: String?
    @State private var contentWidth: CGFloat = 640

    private static let horizontalPadding: CGFloat = 14

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(elements) { element in
                    render(element)
                }
            }
            .padding(MarkdownView.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: MarkdownWidthKey.self, value: proxy.size.width)
            })
        }
        .onPreferenceChange(MarkdownWidthKey.self) { width in
            if width > 0 { contentWidth = width }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "mailto" {
                return .systemAction
            }
            return onLink?(url) ?? .discarded
        })
        .task(id: text) {
            guard parsedText != text else { return }
            let source = text
            let parsed = await Task.detached(priority: .userInitiated) { MarkdownParser.parse(source) }.value
            elements = parsed
            parsedText = source
        }
    }

    @ViewBuilder
    private func render(_ element: MarkdownElement) -> some View {
        switch element.kind {
        case .header(let level):
            Text(element.text)
                .font(MarkdownView.headerFont(level))
                .padding(.top, level <= 2 ? 10 : 6)
                .padding(.leading, CGFloat(element.indent) * 18)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let marker = element.marker {
                    Text(marker)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                } else if element.indent > 0 {
                    Color.clear.frame(width: 18, height: 1)
                }
                Text(element.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(max(element.indent - 1, 0)) * 18)
            .modifier(QuoteStyle(depth: element.quoteDepth, accent: theme.accentColor))
        case .code(let language):
            CodeBlockView(code: element.plainText, language: language, accent: theme.accentColor)
                .padding(.leading, CGFloat(element.indent) * 18)
                .modifier(QuoteStyle(depth: element.quoteDepth, accent: theme.accentColor))
        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        case .table(let rows, let hasHeader, let alignments):
            MarkdownTableView(rows: rows, hasHeader: hasHeader, alignments: alignments,
                              availableWidth: max(contentWidth - 2 * MarkdownView.horizontalPadding - CGFloat(element.indent) * 18, 160))
                .padding(.leading, CGFloat(element.indent) * 18)
                .padding(.vertical, 4)
        }
    }

    static func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}

/// A left bar per quote level.
private struct QuoteStyle: ViewModifier {
    let depth: Int
    let accent: Color

    func body(content: Content) -> some View {
        if depth > 0 {
            HStack(spacing: 8) {
                ForEach(0..<depth, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent.opacity(0.6))
                        .frame(width: 3)
                }
                content
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }
}

/// Monospaced code with a copy button — the point of a cheat sheet.
struct CodeBlockView: View {
    let code: String
    let language: String?
    let accent: Color
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
                    .padding(.leading, 10)
                    .padding(.trailing, 44)
            }
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? Color.green : accent)
                }
                .buttonStyle(.plain)
                .help("Copy this block")
            }
            .padding(6)
        }
    }
}

private struct MarkdownWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Column alignment from the delimiter row (`:---`, `---:`, `:---:`).
enum MarkdownColumnAlignment: Sendable {
    case leading
    case center
    case trailing

    var alignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// A Markdown table laid out like a web page would: columns as wide as their content when that
/// fits, otherwise shared out proportionally with the text wrapping, and only scrolled
/// horizontally when even the longest words do not fit. Header row tinted and bold, zebra rows.
struct MarkdownTableView: View {
    let rows: [[AttributedString]]
    let hasHeader: Bool
    let alignments: [MarkdownColumnAlignment]
    let availableWidth: CGFloat

    private static let fontSize: CGFloat = 12
    private static let cellPaddingHorizontal: CGFloat = 8
    private static let cellPaddingVertical: CGFloat = 5
    private static let longestWordCap: CGFloat = 260

    private var columnCount: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        let widths = columnWidths()
        let total = widths.reduce(0, +)
        Group {
            if total > availableWidth + 0.5 {
                ScrollView(.horizontal, showsIndicators: true) {
                    grid(widths: widths)
                }
            } else {
                grid(widths: widths)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func grid(widths: [CGFloat]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                let isHeader = hasHeader && rowIndex == 0
                GridRow {
                    ForEach(0..<max(columnCount, 1), id: \.self) { column in
                        let alignment = column < alignments.count ? alignments[column] : .leading
                        Group {
                            if column < row.count {
                                Text(row[column])
                                    .font(isHeader ? .callout.weight(.semibold) : .callout)
                                    .multilineTextAlignment(alignment.textAlignment)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("")
                            }
                        }
                        .padding(.horizontal, MarkdownTableView.cellPaddingHorizontal)
                        .padding(.vertical, MarkdownTableView.cellPaddingVertical)
                        .frame(width: column < widths.count ? widths[column] : 80, alignment: alignment.alignment)
                        .background(isHeader ? Color.white.opacity(0.12) : (rowIndex % 2 == (hasHeader ? 0 : 1) ? Color.white.opacity(0.04) : Color.clear))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(isHeader ? 0.2 : 0.07))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    /// Natural widths when they fit; otherwise the longest word of each column as a floor (capped)
    /// and the rest shared in proportion to what each column would like.
    private func columnWidths() -> [CGFloat] {
        let columns = max(columnCount, 1)
        var ideal = [CGFloat](repeating: 0, count: columns)
        var minimum = [CGFloat](repeating: 0, count: columns)
        let padding = 2 * MarkdownTableView.cellPaddingHorizontal
        for row in rows {
            for (index, cell) in row.enumerated() where index < columns {
                let measured = MarkdownTableView.measure(cell)
                ideal[index] = max(ideal[index], measured.width + padding + 1)
                minimum[index] = max(minimum[index], min(measured.longestWord, MarkdownTableView.longestWordCap) + padding + 1)
            }
        }
        for index in 0..<columns {
            ideal[index] = max(ideal[index], 24 + padding)
            minimum[index] = max(minimum[index], 24 + padding)
        }
        let idealTotal = ideal.reduce(0, +)
        if idealTotal <= availableWidth { return ideal }
        let floorTotal = minimum.reduce(0, +)
        if floorTotal >= availableWidth { return minimum }   // scrolls horizontally
        let extra = availableWidth - floorTotal
        let flex = (0..<columns).map { max(ideal[$0] - minimum[$0], 0) }
        let flexTotal = flex.reduce(0, +)
        return (0..<columns).map { index in
            minimum[index] + (flexTotal > 0 ? extra * flex[index] / flexTotal : extra / CGFloat(columns))
        }
    }

    /// Width of a cell's widest line, and of its longest word, with the fonts Text will use.
    private static func measure(_ cell: AttributedString) -> (width: CGFloat, longestWord: CGFloat) {
        let regular = NSFont.systemFont(ofSize: fontSize)
        let bold = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        var lines: [NSMutableAttributedString] = [NSMutableAttributedString()]
        var longestWord: CGFloat = 0
        for run in cell.runs {
            let piece = String(cell[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            let font = intent.contains(.code) ? mono : (intent.contains(.stronglyEmphasized) ? bold : regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            for (index, part) in piece.components(separatedBy: "\n").enumerated() {
                if index > 0 { lines.append(NSMutableAttributedString()) }
                lines[lines.count - 1].append(NSAttributedString(string: part, attributes: attributes))
                for word in part.split(whereSeparator: { $0.isWhitespace }) {
                    longestWord = max(longestWord, (String(word) as NSString).size(withAttributes: attributes).width)
                }
            }
        }
        let width = lines.map { $0.size().width }.max() ?? 0
        return (width, longestWord)
    }
}

// MARK: - Parsing

/// One laid-out piece of a document.
struct MarkdownElement: Identifiable, Sendable {
    enum Kind: Sendable {
        case header(Int)
        case paragraph
        case code(String?)
        case thematicBreak
        case table(rows: [[AttributedString]], hasHeader: Bool, alignments: [MarkdownColumnAlignment])
    }

    let id: Int
    let kind: Kind
    var text: AttributedString
    /// List nesting (0 = not in a list).
    var indent: Int = 0
    /// "•" or "3." for the first block of a list item.
    var marker: String? = nil
    var quoteDepth: Int = 0

    var plainText: String {
        var string = String(text.characters)
        while string.hasSuffix("\n") { string.removeLast() }
        return string
    }
}

/// A pipe table cut out of the source before Foundation parses the rest.
struct MarkdownTable: Sendable {
    var rows: [[AttributedString]]
    var hasHeader: Bool
    var alignments: [MarkdownColumnAlignment]
}

enum MarkdownParser {
    /// Stands in for a table in the text handed to Foundation (U+FFFC never occurs in prose).
    static let tablePlaceholder = "\u{FFFC}LUIK-TABLE:"

    /// Blocks in document order. Falls back to one paragraph per line when the parser rejects
    /// the text (it is lenient, so that is rare).
    static func parse(_ source: String) -> [MarkdownElement] {
        let (text, tables) = extractTables(source.replacingOccurrences(of: "\r\n", with: "\n"))
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true,
                                                              interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let attributed = try? AttributedString(markdown: text, options: options) else {
            return text.components(separatedBy: "\n\n").enumerated().map { index, paragraph in
                MarkdownElement(id: index, kind: .paragraph, text: AttributedString(paragraph))
            }
        }

        // 1. Group runs into blocks: consecutive runs with the same presentation intent.
        struct RawBlock {
            var intent: PresentationIntent?
            var text: AttributedString
        }
        var raw: [RawBlock] = []
        for run in attributed.runs {
            var piece = AttributedString(attributed[run.range])
            piece.presentationIntent = nil
            if let last = raw.indices.last, raw[last].intent == run.presentationIntent {
                raw[last].text.append(piece)
            } else {
                raw.append(RawBlock(intent: run.presentationIntent, text: piece))
            }
        }

        // 2. Classify each block; table cells are collected into tables.
        var elements: [MarkdownElement] = []
        var lastListItemIdentity: Int? = nil
        var tableRows: [[AttributedString]] = []
        var tableHasHeader = false
        var tableIdentity: Int? = nil
        var currentRowIdentity: Int? = nil
        var tableIndent = 0

        func flushTable() {
            guard tableIdentity != nil else { return }
            var element = MarkdownElement(id: elements.count, kind: .table(rows: tableRows, hasHeader: tableHasHeader, alignments: []), text: AttributedString())
            element.indent = tableIndent
            elements.append(element)
            tableRows = []
            tableHasHeader = false
            tableIdentity = nil
            currentRowIdentity = nil
        }

        for block in raw {
            // Innermost component first (children are created after their parents, so a higher
            // identity means deeper nesting).
            let components = (block.intent?.components ?? []).sorted { $0.identity > $1.identity }
            var kind: MarkdownElement.Kind = .paragraph
            var indent = 0
            var quoteDepth = 0
            var listItem: (identity: Int, ordinal: Int)? = nil
            var listIsOrdered = false
            var tableCell: (table: Int, row: Int, isHeader: Bool)? = nil
            var sawListForItem = false

            for component in components {
                switch component.kind {
                case .header(let level):
                    kind = .header(level)
                case .codeBlock(let language):
                    kind = .code(language)
                case .thematicBreak:
                    kind = .thematicBreak
                case .blockQuote:
                    quoteDepth += 1
                case .listItem(let ordinal):
                    if listItem == nil {
                        listItem = (component.identity, ordinal)
                    }
                case .orderedList:
                    indent += 1
                    if listItem != nil && !sawListForItem {
                        listIsOrdered = true
                        sawListForItem = true
                    }
                case .unorderedList:
                    indent += 1
                    if listItem != nil && !sawListForItem {
                        sawListForItem = true
                    }
                case .tableCell:
                    break
                case .tableHeaderRow:
                    if let cell = tableCell { tableCell = (cell.table, component.identity, true) }
                    else { tableCell = (0, component.identity, true) }
                case .tableRow:
                    if let cell = tableCell { tableCell = (cell.table, component.identity, cell.isHeader) }
                    else { tableCell = (0, component.identity, false) }
                case .table:
                    if let cell = tableCell { tableCell = (component.identity, cell.row, cell.isHeader) }
                    else { tableCell = (component.identity, 0, false) }
                case .paragraph:
                    break
                @unknown default:
                    break
                }
            }

            if let cell = tableCell {
                if tableIdentity != cell.table {
                    flushTable()
                    tableIdentity = cell.table
                    tableIndent = indent
                }
                if currentRowIdentity != cell.row {
                    currentRowIdentity = cell.row
                    tableRows.append([])
                    if cell.isHeader { tableHasHeader = true }
                }
                if !tableRows.isEmpty {
                    tableRows[tableRows.count - 1].append(block.text)
                }
                continue
            }
            flushTable()

            if case .thematicBreak = kind {
                elements.append(MarkdownElement(id: elements.count, kind: .thematicBreak, text: AttributedString()))
                continue
            }

            // A placeholder paragraph stands for a table that was cut out of the source.
            if case .paragraph = kind, let table = MarkdownParser.table(forPlaceholder: String(block.text.characters), in: tables) {
                var element = MarkdownElement(id: elements.count, kind: .table(rows: table.rows, hasHeader: table.hasHeader, alignments: table.alignments), text: AttributedString())
                element.indent = indent
                element.quoteDepth = quoteDepth
                if let listItem, lastListItemIdentity != listItem.identity {
                    lastListItemIdentity = listItem.identity
                }
                elements.append(element)
                continue
            }

            var element = MarkdownElement(id: elements.count, kind: kind, text: block.text)
            element.indent = indent
            element.quoteDepth = quoteDepth
            if let listItem {
                if lastListItemIdentity != listItem.identity {
                    element.marker = listIsOrdered ? "\(listItem.ordinal)." : "•"
                    lastListItemIdentity = listItem.identity
                }
            } else {
                lastListItemIdentity = nil
            }
            // A block with nothing but whitespace (e.g. a stray newline) is not worth a row.
            if case .paragraph = kind, element.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            elements.append(element)
        }
        flushTable()
        return elements
    }

    // MARK: Pipe tables

    static func table(forPlaceholder text: String, in tables: [MarkdownTable]) -> MarkdownTable? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(tablePlaceholder), trimmed.hasSuffix("\u{FFFC}") else { return nil }
        let number = trimmed.dropFirst(tablePlaceholder.count).dropLast()
        guard let index = Int(number), index >= 0, index < tables.count else { return nil }
        return tables[index]
    }

    /// Replaces every pipe table (header row, delimiter row, body rows) by a placeholder
    /// paragraph and returns the tables with their cells parsed as inline Markdown. Fenced code
    /// is left alone.
    static func extractTables(_ text: String) -> (String, [MarkdownTable]) {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var tables: [MarkdownTable] = []
        var fence: String? = nil
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker(trimmed) {
                if let open = fence {
                    if marker.hasPrefix(String(open.first!)) && marker.count >= open.count { fence = nil }
                } else {
                    fence = marker
                }
                output.append(line)
                index += 1
                continue
            }
            if fence == nil, index + 1 < lines.count, isTableRow(trimmed),
               let alignments = delimiterRow(lines[index + 1]) {
                let header = splitCells(trimmed)
                if header.count == alignments.count {
                    var rows: [[String]] = [header]
                    var next = index + 2
                    while next < lines.count {
                        let candidate = lines[next].trimmingCharacters(in: .whitespaces)
                        guard isTableRow(candidate) else { break }
                        rows.append(splitCells(candidate))
                        next += 1
                    }
                    let columns = max(rows.map(\.count).max() ?? 0, alignments.count)
                    let padded = rows.map { row in row + Array(repeating: "", count: max(columns - row.count, 0)) }
                    var columnAlignments = alignments
                    while columnAlignments.count < columns { columnAlignments.append(.leading) }
                    tables.append(MarkdownTable(rows: padded.map { $0.map(inlineCell) }, hasHeader: true, alignments: columnAlignments))
                    let indent = String(line.prefix { $0 == " " || $0 == "\t" })
                    if let last = output.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { output.append("") }
                    output.append(indent + tablePlaceholder + "\(tables.count - 1)" + "\u{FFFC}")
                    output.append("")
                    index = next
                    continue
                }
            }
            output.append(line)
            index += 1
        }
        return (output.joined(separator: "\n"), tables)
    }

    /// "```" / "~~~" (three or more) at the start of a line.
    private static func fenceMarker(_ trimmed: String) -> String? {
        for character in ["`", "~"] {
            let run = trimmed.prefix { String($0) == character }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    private static func isTableRow(_ trimmed: String) -> Bool {
        !trimmed.isEmpty && trimmed.contains("|") && fenceMarker(trimmed) == nil
    }

    /// `| :--- | ---: | :---: |` → alignments, or nil when the line is not a delimiter row.
    private static func delimiterRow(_ line: String) -> [MarkdownColumnAlignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }
        var alignments: [MarkdownColumnAlignment] = []
        for cell in splitCells(trimmed) {
            let compact = cell.replacingOccurrences(of: " ", with: "")
            guard !compact.isEmpty else { return nil }
            let left = compact.hasPrefix(":")
            let right = compact.hasSuffix(":")
            let dashes = compact.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(left && right ? .center : (right ? .trailing : .leading))
        }
        return alignments.isEmpty ? nil : alignments
    }

    /// Cells of a row; outer pipes are optional, `\|` is a literal pipe.
    private static func splitCells(_ trimmed: String) -> [String] {
        let sentinel = "\u{E000}"
        var text = trimmed.replacingOccurrences(of: "\\|", with: sentinel)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map {
            $0.replacingOccurrences(of: sentinel, with: "|").trimmingCharacters(in: .whitespaces)
        }
    }

    /// Inline Markdown of a cell; `<br>` becomes a line break.
    private static func inlineCell(_ raw: String) -> AttributedString {
        var text = raw
        for tag in ["<br>", "<br/>", "<br />", "<BR>", "<BR/>", "<BR />"] {
            text = text.replacingOccurrences(of: tag, with: "\n")
        }
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true,
                                                              interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}
