import AppKit
import SwiftUI

/// The Tools tab: a sidebar with the modules that are not in the top bar — small tools and
/// whichever tabs you moved here — and the chosen one on the right. Every module stays mounted.
struct ToolsView: View {
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme

    @AppStorage("toolsSidebarCollapsed") private var collapsed = false

    var body: some View {
        if collapsed {
            HStack(spacing: 0) {
                iconRail
                Divider()
                content
            }
        } else {
            SplitPane(storageKey: "toolsSplitFraction", defaultFraction: 0.22, minFraction: 0.14, maxFraction: 0.4) {
                sidebar
            } trailing: {
                content
            }
        }
    }

    /// Collapsed sidebar: one icon per tool, the selected one tinted, names as tooltips.
    private var iconRail: some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { collapsed = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show the tool names")
            .padding(.bottom, 4)
            ForEach(Module.toolGroupOrder, id: \.self) { group in
                let members = ui.toolOrder.filter { $0.toolGroup == group }
                if !members.isEmpty {
                    if group != Module.toolGroupOrder.first(where: { g in ui.toolOrder.contains { $0.toolGroup == g } }) {
                        Divider().padding(.vertical, 3).padding(.horizontal, 8)
                    }
                    ForEach(members) { module in
                        Button {
                            ui.open(module)
                        } label: {
                            Image(systemName: module.icon)
                                .font(.system(size: 15))
                                .frame(width: 34, height: 30)
                                .background(ui.module == module ? theme.accentColor.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(ui.module == module ? theme.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help(module.title + " — " + module.summary)
                        .contextMenu {
                            Button("Move up") { ui.moveTool(module, by: -1) }
                                .disabled(ui.toolOrder.first == module)
                            Button("Move down") { ui.moveTool(module, by: 1) }
                                .disabled(ui.toolOrder.last == module)
                            Divider()
                            Button("Give it a tab in the top bar") { ui.moveToTabs(module) }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: 44)
    }

    private var sidebar: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("Tools")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { collapsed = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Collapse to icons")
                    Menu {
                        Button("Collapse sidebar to icons") { withAnimation(.easeOut(duration: 0.15)) { collapsed = true } }
                        Divider()
                        Button("Reset tabs and tools") { ui.resetLayout() }
                            .disabled(ui.isDefaultLayout)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                List(selection: Binding<Module?>(get: { ui.toolOrder.contains(ui.module) ? ui.module : nil },
                                                 set: { if let module = $0 { ui.open(module) } })) {
                    ForEach(Module.toolGroupOrder, id: \.self) { group in
                        let members = ui.toolOrder.filter { $0.toolGroup == group }
                        if !members.isEmpty {
                            Section(group) {
                                ForEach(members) { module in
                                    Label(module.title, systemImage: module.icon)
                                        .help(module.summary)
                                        .tag(module)
                                        .contextMenu {
                                            Button("Move up") { ui.moveTool(module, by: -1) }
                                                .disabled(ui.toolOrder.first == module)
                                            Button("Move down") { ui.moveTool(module, by: 1) }
                                                .disabled(ui.toolOrder.last == module)
                                            Divider()
                                            Button("Give it a tab in the top bar") { ui.moveToTabs(module) }
                                        }
                                }
                            }
                        }
                    }
                    if ui.toolOrder.isEmpty {
                        Text("Everything has its own tab. Right-click a tab and choose “Move into Tools” to park it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
    }

    private var content: some View {
            ZStack {
                ForEach(ui.toolOrder) { module in
                    ModuleContent(module: module)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(ui.module == module ? 1 : 0)
                        .allowsHitTesting(ui.module == module)
                        .accessibilityHidden(ui.module != module)
                        .zIndex(ui.module == module ? 1 : 0)
                }
                if !ui.toolOrder.contains(ui.module) {
                    VStack {
                        Spacer()
                        Text(ui.toolOrder.isEmpty ? "No tools here." : "Choose a tool in the sidebar.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            EmptyState(icon: "clock.badge.exclamationmark", title: "Version & end of life",
                       message: "Type a product and pick it from the list; add the version you found for a verdict. Check ▾ › Version on a port node in Targets fills it in.")
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


/// Mail security check for a domain.
struct MailSecurityView: View {
    @Environment(FindingsStore.self) private var findings
    @Environment(\.luikTheme) private var theme
    @State private var showRecords = false

    var body: some View {
        @Bindable var check = MailSecurityCheck.shared
        VStack(spacing: 0) {
            CheckToolbar(text: $check.domain, placeholder: "Mail domain (example.com)", isRunning: check.isRunning, hasOptions: true, optionsHelp: "Extra DKIM selectors", run: { check.run() }) {
                Text("Extra DKIM selectors").font(.caption.weight(.semibold))
                TextField("comma-separated, e.g. mail2024, sel1", text: $check.selectors)
                    .textFieldStyle(.roundedBorder)
                Text("Common selectors are tried automatically; add the one from a real mail's DKIM-Signature header (s=…) when it is not among them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } trailing: {
                if let result = check.result {
                    CheckResultButtons(markdown: { MailSecurityCheck.markdown(result) },
                                       findingTitle: result.problems.isEmpty ? nil : "Weak email authentication for \(result.domain)",
                                       createFinding: { createFinding(result) },
                                       addToTargets: nil)
                }
            }
            Divider()
            if let error = check.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if let result = check.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(result.domain)
                                .font(.title2.weight(.semibold))
                            Text("\(result.problems.filter { $0.level == .fail }.count) failing · \(result.problems.filter { $0.level == .warn }.count) warnings · checked \(result.checkedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: symbol(item.level))
                                    .foregroundStyle(color(item.level))
                                    .frame(width: 16)
                                Text(item.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(color(item.level).opacity(item.level == .pass ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                        if !result.spfExpanded.isEmpty || !result.dkim.isEmpty {
                            DisclosureGroup(isExpanded: $showRecords) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(result.spfExpanded.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                    ForEach(Array(result.dkim.enumerated()), id: \.offset) { _, key in
                                        Text("\(key.selector)._domainkey.\(result.domain): \(key.record)")
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                Text("Records: \(result.spfExpanded.count) SPF include(s), \(result.dkim.count) DKIM key(s) — \(result.selectorsTried.count) selectors tried")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyState(icon: "envelope.badge.shield.half.filled", title: "Mail security",
                           message: "SPF, DKIM, DMARC, MX, MTA-STS and TLS-RPT of a domain, judged. Only DNS queries through dig.")
            }
        }
    }

    private func symbol(_ level: MailCheckItem.Level) -> String {
        switch level {
        case .pass: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    private func color(_ level: MailCheckItem.Level) -> Color {
        switch level {
        case .pass: return .green
        case .info: return .secondary
        case .warn: return .yellow
        case .fail: return .red
        }
    }

    private func createFinding(_ result: MailSecurityResult) {
        var finding = Finding(title: "Weak email authentication for \(result.domain)")
        let fails = result.problems.filter { $0.level == .fail }
        if fails.contains(where: { $0.text.contains("+all") }) {
            finding.severity = .high
        } else if !fails.isEmpty {
            finding.severity = .medium
        } else {
            finding.severity = .low
        }
        finding.description = "Issues:\n" + result.problems.map { "- \($0.text)" }.joined(separator: "\n")
            + "\n\nRecords:\n" + result.items.filter { $0.level == .pass && ($0.text.hasPrefix("SPF:") || $0.text.hasPrefix("DMARC:") || $0.text.hasPrefix("MX:")) }.map { "- \($0.text)" }.joined(separator: "\n")
        finding.impact = "Mail that appears to come from @\(result.domain) can be forged and is accepted or at least not rejected by receiving systems — the basis for phishing of customers, partners and staff in the organisation's name."
        finding.recommendation = "Publish a single SPF record that lists all legitimate senders within 10 DNS lookups and ends in -all; sign outbound mail with DKIM (2048-bit keys); publish a DMARC record with p=reject (via quarantine, with pct ramp-up) and rua= reporting; consider MTA-STS and TLS-RPT for transport security."
        finding.affected = [result.domain]
        finding.source = "Mail security check"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the mail security check", source: "Tools")
    }
}


/// Reachability canary: which hosts to probe, how often, and how they are doing.
struct CanaryView: View {
    @Environment(TargetStore.self) private var targets
    @Environment(\.luikTheme) private var theme
    @State private var address = ""
    @State private var port = ""
    @State private var label = ""

    var body: some View {
        let canary = CanaryStore.shared
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("Enabled for this engagement", isOn: Binding(get: { canary.config.enabled }, set: { canary.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .disabled(canary.config.targets.isEmpty && !canary.config.enabled)
                Picker("Every", selection: Binding(get: { canary.config.intervalMinutes }, set: { canary.setInterval($0) })) {
                    ForEach(CanaryStore.intervals, id: \.self) { minutes in
                        Text(minutes == 60 ? "hour" : "\(minutes) min").tag(minutes)
                    }
                }
                .frame(maxWidth: 160)
                Button {
                    canary.checkNow()
                } label: {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .disabled(canary.config.targets.isEmpty || canary.isChecking)
                if canary.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if let last = canary.lastRun {
                    Text("Last check \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Every probe is traffic to the client's systems: a TCP connect to a port you know is open, or one ICMP echo. Pick one or two hosts that are in scope and expected to answer, keep the interval modest, and switch it off when you stop testing. A change from reachable to unreachable (and back) is written to the Log with the time — that timestamp is what you quote when a block is discussed. The setting is per engagement and off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if canary.config.targets.isEmpty {
                        Text("No targets yet — add a host below, or pick one from Targets.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(canary.config.targets) { target in
                            targetRow(target, canary: canary)
                        }
                    }

                    Divider()
                    Text("Add a target")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        TextField("Host or IP", text: $address)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        TextField("Port (empty = ping)", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        TextField("Label (optional)", text: $label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button("Add") { addManual(canary) }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                        Menu {
                            if targets.hosts.isEmpty {
                                Text("No hosts in Targets")
                            }
                            ForEach(targets.hosts) { host in
                                let ports = host.children.filter { $0.kind == .port }
                                Menu(host.address.isEmpty ? host.title : host.address) {
                                    Button("Ping \(host.address)") {
                                        canary.add(CanaryTarget(address: host.address, port: nil, label: host.subtitle))
                                    }
                                    ForEach(ports) { portNode in
                                        Button("\(host.address):\(portNode.portNumber) \(TargetStore.serviceName(of: portNode))") {
                                            canary.add(CanaryTarget(address: host.address, port: portNode.portNumber, label: TargetStore.serviceName(of: portNode)))
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("From Targets", systemImage: "network")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func addManual(_ canary: CanaryStore) {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        let portNumber = Int(port.trimmingCharacters(in: .whitespaces))
        canary.add(CanaryTarget(address: host, port: portNumber, label: label.trimmingCharacters(in: .whitespaces)))
        address = ""
        port = ""
        label = ""
    }

    private func targetRow(_ target: CanaryTarget, canary: CanaryStore) -> some View {
        let state = canary.state(for: target)
        return HStack(spacing: 10) {
            Circle()
                .fill(state.status == .up ? Color.green : (state.status == .down ? Color.red : Color.gray))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.display)
                        .font(.callout.weight(.semibold))
                    if !target.label.isEmpty {
                        Text(target.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(statusLine(state))
                    .font(.caption)
                    .foregroundStyle(state.status == .down ? Color.red : Color.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(state.history.enumerated()), id: \.offset) { _, up in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(up ? Color.green.opacity(0.8) : Color.red.opacity(0.9))
                        .frame(width: 5, height: 12)
                }
            }
            .help("Recent results, oldest left")
            Button {
                canary.check(target)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Check this target now")
            Button(role: .destructive) {
                canary.remove(target.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusLine(_ state: CanaryState) -> String {
        var parts = [state.status.label]
        if let latency = state.latencyMs { parts.append(String(format: "%.0f ms", latency)) }
        if let checked = state.lastChecked { parts.append("checked \(checked.formatted(date: .omitted, time: .shortened))") }
        if let change = state.lastChange { parts.append("since \(change.formatted(date: .omitted, time: .shortened))") }
        if !state.detail.isEmpty && state.status == .down { parts.append(state.detail) }
        return parts.joined(separator: " · ")
    }
}
