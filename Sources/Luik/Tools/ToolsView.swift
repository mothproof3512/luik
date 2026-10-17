import AppKit
import SwiftUI

/// Small tools that do not deserve a tab of their own: a sidebar of tools, the chosen one on the right.
enum ToolKind: String, CaseIterable, Identifiable {
    case versionCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .versionCheck: return "Version & end-of-life check"
        }
    }

    var icon: String {
        switch self {
        case .versionCheck: return "clock.badge.exclamationmark"
        }
    }

    var summary: String {
        switch self {
        case .versionCheck: return "Is this version current, supported or end of life? Cycles and dates from endoflife.date, release notes from GitHub."
        }
    }
}

struct ToolsView: View {
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme

    var body: some View {
        SplitPane(storageKey: "toolsSplitFraction", defaultFraction: 0.22, minFraction: 0.14, maxFraction: 0.4) {
            VStack(spacing: 0) {
                HStack {
                    Text("Tools")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                List(selection: Binding<ToolKind?>(get: { ui.tool }, set: { if let tool = $0 { ui.tool = tool } })) {
                    ForEach(ToolKind.allCases) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(tool.title, systemImage: tool.icon)
                            Text(tool.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tag(tool)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        } trailing: {
            switch ui.tool {
            case .versionCheck:
                VersionCheckView()
            }
        }
    }
}

/// Version & end-of-life check.
struct VersionCheckView: View {
    @Environment(UIState.self) private var ui
    @Environment(FindingsStore.self) private var findings
    @Environment(\.luikTheme) private var theme
    @State private var findingCreated = false

    var body: some View {
        @Bindable var check = VersionCheck.shared
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Product (apache, openssh, windows server, php, …)", text: $check.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit {
                        if let first = check.matches.first { check.select(first) }
                    }
                TextField("Version found (optional)", text: $check.version)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                if check.isLoadingProducts {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if let at = check.productsFetchedAt {
                    Text("\(check.products.count) products · list from \(at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    check.loadProductsIfNeeded(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the product list from endoflife.date")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            HStack(spacing: 0) {
                matchesList
                    .frame(width: 230)
                Divider()
                detail
            }
        }
        .onAppear { VersionCheck.shared.loadProductsIfNeeded() }
    }

    private var matchesList: some View {
        let check = VersionCheck.shared
        let matches = check.matches
        return List(selection: Binding(get: { check.selectedProduct?.name }, set: { name in
            if let name, let product = check.products.first(where: { $0.name == name }) { check.select(product) }
        })) {
            if check.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(check.products.isEmpty ? "Loading the product list…" : "Type a product name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if matches.isEmpty {
                Text(check.products.isEmpty ? "The product list is not loaded yet." : "No product matches — endoflife.date tracks about \(check.products.count) products.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(matches) { product in
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.label)
                        .lineLimit(1)
                    Text(product.category + (product.aliases.isEmpty ? "" : " · " + product.aliases.joined(separator: ", ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(product.name)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var detail: some View {
        let check = VersionCheck.shared
        if let error = check.error, check.detail == nil {
            VStack {
                Spacer()
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if check.isLoadingDetail {
            VStack {
                Spacer()
                ProgressView("Loading \(check.selectedProduct?.label ?? "")…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let detail = check.detail {
            productDetail(detail)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Type a product and pick it from the list; add the version you found to get a verdict.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("On a port node in Targets, the Version button brings the product and version here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func productDetail(_ detail: EOLProductDetail) -> some View {
        @Bindable var check = VersionCheck.shared
        let verdict = check.verdict(for: check.version, in: detail)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(detail.label)
                        .font(.title2.weight(.semibold))
                    if let category = detail.category {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let html = detail.links?.html, let url = URL(string: html) {
                        Link("endoflife.date", destination: url)
                            .font(.caption)
                    }
                    if let policy = detail.links?.releasePolicy, let url = URL(string: policy) {
                        Link("Release policy", destination: url)
                            .font(.caption)
                    }
                }

                if !verdict.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(for: verdict.severity))
                                .foregroundStyle(color(for: verdict.severity))
                            Text(verdict.summary)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if verdict.severity != .fine && verdict.severity != .unknown {
                                Button {
                                    createFinding(detail: detail, verdict: verdict)
                                } label: {
                                    Label(findingCreated ? "Finding created" : "Create finding", systemImage: findingCreated ? "checkmark" : "exclamationmark.triangle")
                                }
                                .help("A finding “Outdated \(detail.label)” with the version, the latest version and the dates in the description; adjust the severity afterwards")
                            }
                        }
                        ForEach(verdict.details, id: \.self) { line in
                            Text("• \(line)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let command = detail.versionCommand, !command.isEmpty {
                            Text("Version command: \(command.replacingOccurrences(of: "\n", with: " · "))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color(for: verdict.severity).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                Text("Release cycles")
                    .font(.subheadline.weight(.semibold))
                cyclesTable(detail, highlighted: verdict.cycle?.name)

                HStack(spacing: 8) {
                    Text("Release notes")
                        .font(.subheadline.weight(.semibold))
                    TextField("GitHub owner/repository", text: $check.repository)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 260)
                        .onSubmit { check.loadReleases() }
                    Button("Load") { check.loadReleases() }
                        .disabled(check.repository.trimmingCharacters(in: .whitespaces).isEmpty)
                    if check.isLoadingReleases {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                if check.releases.isEmpty {
                    Text(check.repository.isEmpty
                         ? "endoflife.date knows no GitHub repository for this product; enter one (owner/name) to read its release notes here."
                         : (check.isLoadingReleases ? "" : "No releases loaded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(check.releases) { release in
                        DisclosureGroup {
                            if let body = release.body, !body.isEmpty {
                                MarkdownView(text: body)
                                    .frame(minHeight: 60, maxHeight: 360)
                                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            } else {
                                Text("No notes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(release.tagName)
                                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                                if let name = release.name, name != release.tagName {
                                    Text(name)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let date = release.publishedAt {
                                    Text(String(date.prefix(10)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let html = release.htmlUrl, let url = URL(string: html) {
                                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cyclesTable(_ detail: EOLProductDetail, highlighted: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("Cycle", width: 110)
                header("Released", width: 100)
                header("Latest", width: 150)
                header("Active support", width: 120)
                header("End of life", width: 120)
                header("Status", width: 150)
            }
            .background(Color.white.opacity(0.1))
            ForEach(detail.releases) { release in
                HStack(spacing: 0) {
                    cell(release.label + (release.isLts ? " LTS" : ""), width: 110, bold: true)
                    cell(release.releaseDate ?? "—", width: 100)
                    cell((release.latest?.name ?? "—") + (release.latest?.date.map { " (\($0))" } ?? ""), width: 150)
                    cell(release.eoasFrom ?? "—", width: 120)
                    cell(release.eolFrom ?? (release.isEol ? "yes" : "—"), width: 120)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor(release.state))
                            .frame(width: 8, height: 8)
                        Text(release.state.label)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 150, alignment: .leading)
                }
                .background(release.name == highlighted ? theme.accentColor.opacity(0.18) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func header(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: width, alignment: .leading)
    }

    private func cell(_ text: String, width: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .font(bold ? .caption.weight(.semibold) : .caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
            .textSelection(.enabled)
    }

    private func stateColor(_ state: EOLRelease.State) -> Color {
        switch state {
        case .eol: return .red
        case .unmaintained: return .orange
        case .securityOnly: return .yellow
        case .maintained: return .green
        }
    }

    private func symbol(for severity: VersionVerdict.Severity) -> String {
        switch severity {
        case .eol, .unmaintained: return "xmark.octagon.fill"
        case .securityOnly, .patchBehind: return "exclamationmark.triangle.fill"
        case .fine: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(for severity: VersionVerdict.Severity) -> Color {
        switch severity {
        case .eol: return .red
        case .unmaintained: return .orange
        case .securityOnly, .patchBehind: return .yellow
        case .fine: return .green
        case .unknown: return .secondary
        }
    }

    private func createFinding(detail: EOLProductDetail, verdict: VersionVerdict) {
        let check = VersionCheck.shared
        var finding = Finding(title: "Outdated \(detail.label) \(check.version.trimmingCharacters(in: .whitespaces))")
        switch verdict.severity {
        case .eol: finding.severity = .high
        case .unmaintained: finding.severity = .medium
        case .securityOnly, .patchBehind: finding.severity = .medium
        default: finding.severity = .low
        }
        finding.description = verdict.summary + "\n\n" + verdict.details.map { "- \($0)" }.joined(separator: "\n")
        finding.impact = "Software past its support window no longer receives security fixes; known and future vulnerabilities remain exploitable."
        let newestName: String = detail.newest?.latest?.name ?? ""
        let newestNote = newestName.isEmpty ? "" : " (newest: \(newestName))"
        finding.recommendation = "Upgrade to a supported, current release\(newestNote) and establish a patch process that follows the vendor's release policy."
        var references: [String] = []
        if let html = detail.links?.html { references.append(html) }
        if let policy = detail.links?.releasePolicy { references.append(policy) }
        finding.references = references.joined(separator: "\n")
        finding.source = "Version check"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the version check", source: "Tools")
        findingCreated = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { findingCreated = false }
    }
}
