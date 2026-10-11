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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(elements) { element in
                    render(element)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        case .table(let rows, let hasHeader):
            MarkdownTableView(rows: rows, hasHeader: hasHeader)
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

/// A Markdown table as a grid; the header row is bold with a rule under it.
struct MarkdownTableView: View {
    let rows: [[AttributedString]]
    let hasHeader: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(index == 0 && hasHeader ? .callout.weight(.semibold) : .callout)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 420, alignment: .leading)
                        }
                    }
                    if index == 0 && hasHeader {
                        Divider()
                    }
                }
            }
            .padding(8)
        }
        .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
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
        case table(rows: [[AttributedString]], hasHeader: Bool)
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

enum MarkdownParser {
    /// Blocks in document order. Falls back to one paragraph per line when the parser rejects
    /// the text (it is lenient, so that is rare).
    static func parse(_ text: String) -> [MarkdownElement] {
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
            var element = MarkdownElement(id: elements.count, kind: .table(rows: tableRows, hasHeader: tableHasHeader), text: AttributedString())
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
}
