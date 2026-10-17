import Foundation

/// A fill-in field on a plan or on an item: "Tester", "Date", "Result", …
struct PlanField: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case text
        case multiline
        case date
        case choice
        case toggle

        var label: String {
            switch self {
            case .text: return "Text"
            case .multiline: return "Multi-line"
            case .date: return "Date"
            case .choice: return "Choice"
            case .toggle: return "Yes / no"
            }
        }
    }

    var id = UUID()
    var label: String
    var kind: Kind = .text
    /// Options for `.choice`.
    var options: [String] = []
    var value: String = ""

    init(id: UUID = UUID(), label: String, kind: Kind = .text, options: [String] = [], value: String = "") {
        self.id = id
        self.label = label
        self.kind = kind
        self.options = options
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case id, label, kind, options, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    var isFilled: Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(kind == .toggle && value != "true") }

    /// A copy with fresh ids and empty values (template → plan).
    func fresh() -> PlanField {
        PlanField(label: label, kind: kind, options: options, value: kind == .toggle ? "false" : "")
    }
}

/// One thing to do or check in a phase.
struct PlanItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// What this is about / how to approach it (from the template; editable).
    var hint: String = ""
    var status: NodeStatus = .todo
    var notes: String = ""
    var fields: [PlanField] = []

    init(id: UUID = UUID(), title: String, hint: String = "", status: NodeStatus = .todo, notes: String = "", fields: [PlanField] = []) {
        self.id = id
        self.title = title
        self.hint = hint
        self.status = status
        self.notes = notes
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey { case id, title, hint, status, notes, fields }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        status = try c.decodeIfPresent(NodeStatus.self, forKey: .status) ?? .todo
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        fields = try c.decodeIfPresent([PlanField].self, forKey: .fields) ?? []
    }

    func fresh() -> PlanItem {
        PlanItem(title: title, hint: hint, fields: fields.map { $0.fresh() })
    }

    /// The template form of a worked plan item: title, hint and field definitions, no answers.
    func asTemplate() -> PlanItem {
        PlanItem(title: title, hint: hint, fields: fields.map { $0.fresh() })
    }
}

/// A phase of the plan: preparation, reconnaissance, … with its items.
struct PlanPhase: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var summary: String = ""
    var items: [PlanItem] = []

    init(id: UUID = UUID(), name: String, summary: String = "", items: [PlanItem] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case id, name, summary, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
    }

    var progress: (done: Int, total: Int) {
        let counted = items.filter { $0.status != .notApplicable }
        return (counted.filter { $0.status == .done }.count, counted.count)
    }

    func fresh() -> PlanPhase {
        PlanPhase(name: name, summary: summary, items: items.map { $0.fresh() })
    }

    func asTemplate() -> PlanPhase {
        PlanPhase(name: name, summary: summary, items: items.map { $0.asTemplate() })
    }
}

/// A test plan of an engagement, made from a template: plan-level fields plus phases with items.
struct Plan: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var templateName: String = ""
    var fields: [PlanField] = []
    var phases: [PlanPhase] = []
    var createdAt = Date()

    init(id: UUID = UUID(), name: String, templateName: String = "", fields: [PlanField] = [], phases: [PlanPhase] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.templateName = templateName
        self.fields = fields
        self.phases = phases
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, templateName, fields, phases, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Plan"
        templateName = try c.decodeIfPresent(String.self, forKey: .templateName) ?? ""
        fields = try c.decodeIfPresent([PlanField].self, forKey: .fields) ?? []
        phases = try c.decodeIfPresent([PlanPhase].self, forKey: .phases) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var progress: (done: Int, total: Int) {
        phases.reduce((0, 0)) { acc, phase in
            let p = phase.progress
            return (acc.0 + p.done, acc.1 + p.total)
        }
    }

    var itemCount: Int { phases.reduce(0) { $0 + $1.items.count } }
}

/// A reusable plan: what a plan looks like before it is filled in. Templates are global
/// (plan-templates.json) and are what you refine after every engagement.
struct PlanTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var summary: String = ""
    var fields: [PlanField] = []
    var phases: [PlanPhase] = []
    var builtIn: Bool = false

    init(id: UUID = UUID(), name: String, summary: String = "", fields: [PlanField] = [], phases: [PlanPhase] = [], builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.summary = summary
        self.fields = fields
        self.phases = phases
        self.builtIn = builtIn
    }

    private enum CodingKeys: String, CodingKey { case id, name, summary, fields, phases, builtIn }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Template"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        fields = try c.decodeIfPresent([PlanField].self, forKey: .fields) ?? []
        phases = try c.decodeIfPresent([PlanPhase].self, forKey: .phases) ?? []
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
    }

    var itemCount: Int { phases.reduce(0) { $0 + $1.items.count } }

    /// A new plan from this template, with fresh ids and empty values.
    func instantiate(name: String? = nil) -> Plan {
        Plan(name: name ?? self.name, templateName: self.name, fields: fields.map { $0.fresh() }, phases: phases.map { $0.fresh() })
    }

    /// A template from a worked plan: the structure and hints, without statuses and answers.
    static func from(_ plan: Plan, name: String) -> PlanTemplate {
        PlanTemplate(name: name, summary: "Saved from the plan “\(plan.name)”", fields: plan.fields.map { $0.fresh() }, phases: plan.phases.map { $0.asTemplate() })
    }

    // MARK: - Built-in templates

    /// The plan-level fields every built-in template starts with.
    static var standardFields: [PlanField] {
        [
            PlanField(label: "Client"),
            PlanField(label: "Reference"),
            PlanField(label: "Tester(s)"),
            PlanField(label: "Start date", kind: .date),
            PlanField(label: "End date", kind: .date),
            PlanField(label: "Scope", kind: .multiline),
            PlanField(label: "Rules of engagement", kind: .multiline),
            PlanField(label: "Contacts (client, escalation)", kind: .multiline),
        ]
    }

    static func item(_ title: String, _ hint: String = "") -> PlanItem {
        PlanItem(title: title, hint: hint)
    }

    static var preparation: PlanPhase {
        PlanPhase(name: "Preparation", summary: "Before the first packet.", items: [
            item("Scope confirmed in writing", "Addresses, domains, applications, accounts; what is explicitly out of scope."),
            item("Rules of engagement agreed", "Test window, allowed techniques, denial-of-service policy, social engineering yes/no, stop criteria."),
            item("Contacts and escalation path known", "Who to call when something breaks, and when the client wants to be informed."),
            item("Source addresses communicated", "So the SOC can tell you apart from a real attacker."),
            item("Test accounts and access received", "VPN, accounts per role, test data; verified before day one."),
            item("Engagement created in Luik", "Scope and exclusions filled in (Engagements), evidence folder, notes."),
        ])
    }

    static var reporting: PlanPhase {
        PlanPhase(name: "Reporting", summary: "What leaves the engagement.", items: [
            item("All findings written with evidence", "Severity, CVSS, affected systems, reproduction steps, screenshots."),
            item("Recommendations reviewed", "Specific, actionable, prioritised."),
            item("Executive summary written", "Risk in business terms; what was and was not tested."),
            item("Client debrief held", "Open questions answered; retest agreed."),
            item("Data cleaned up", "Test accounts, uploaded files and shells removed; client data on your side handled per policy."),
        ])
    }

    static let builtIn: [PlanTemplate] = [
        PlanTemplate(name: "External network penetration test",
                     summary: "Internet-facing infrastructure: from OSINT to exploitation within the rules of engagement.",
                     fields: standardFields,
                     phases: [
                        preparation,
                        PlanPhase(name: "Reconnaissance", summary: "What the outside world can see.", items: [
                            item("OSINT on the organisation", "Employees, technologies, leaked credentials, public documents, job adverts."),
                            item("Domain and subdomain inventory", "DNS records, certificate transparency, passive sources; compare with the scope."),
                            item("Mail security configuration", "SPF, DKIM, DMARC on every mail domain."),
                            item("Cloud and third-party assets", "Storage buckets, SaaS tenants, dangling DNS."),
                            item("Reconnaissance results into Targets", "Hosts and services as nodes, scope check against the engagement."),
                        ]),
                        PlanPhase(name: "Scanning and enumeration", summary: "Every open door, listed.", items: [
                            item("Port scan of all in-scope addresses", "TCP full range, top UDP; results imported into Targets."),
                            item("Service and version identification"),
                            item("Web technologies and TLS configuration per site"),
                            item("Checklists applied per host and service", "Targets › Apply checklists to all targets."),
                        ]),
                        PlanPhase(name: "Vulnerability analysis", summary: "From observation to confirmed weakness.", items: [
                            item("Known vulnerabilities per version", "Searchsploit and the knowledge base; verify, do not trust scanner output blindly."),
                            item("Default and weak credentials", "Within the rules of engagement (lockout policy!)."),
                            item("Misconfigurations and information disclosure"),
                            item("Web application testing per site", "Use the web application plan for each major application."),
                        ]),
                        PlanPhase(name: "Exploitation", summary: "Only what the rules of engagement allow.", items: [
                            item("Exploitation approved for the target", "Check the RoE and inform the contact when required."),
                            item("Proof of impact collected", "Minimal, reversible, documented; no data taken beyond the proof."),
                            item("Post-exploitation limited to the agreed depth"),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Internal network and Active Directory",
                     summary: "From a foothold on the LAN to domain-level findings.",
                     fields: standardFields + [PlanField(label: "Starting position", kind: .choice, options: ["Unauthenticated on the LAN", "Low-privileged domain user", "Assumed breach workstation", "Other"])],
                     phases: [
                        preparation,
                        PlanPhase(name: "Network discovery", summary: "What is on the wire.", items: [
                            item("Network segments and routing understood"),
                            item("Host discovery and port scans per segment", "Import into Targets; mark canary hosts if reachability matters."),
                            item("Network protections observed", "NAC, 802.1X, segmentation, egress filtering."),
                            item("Network diagram drawn", "Diagram tab: segments, key systems, trust relationships."),
                        ]),
                        PlanPhase(name: "Active Directory enumeration", summary: "Users, groups, machines, trusts, policies.", items: [
                            item("Domain, forest and trust overview"),
                            item("Users, groups and privileged accounts enumerated"),
                            item("Password policy and lockout thresholds known", "Before any password attack."),
                            item("Shares, GPOs and scripts reviewed for secrets"),
                            item("Certificate services reviewed", "Templates and permissions."),
                        ]),
                        PlanPhase(name: "Credential access", summary: "Ways to obtain or abuse credentials.", items: [
                            item("Name resolution and relay opportunities checked"),
                            item("Kerberos-based attacks evaluated", "Within the RoE; note every account targeted."),
                            item("Password attacks executed within the policy", "Spraying cadence agreed with the lockout policy."),
                        ]),
                        PlanPhase(name: "Lateral movement and privilege escalation", summary: "From one system to many.", items: [
                            item("Local privilege escalation on obtained hosts"),
                            item("Reuse of credentials across systems"),
                            item("Delegation and ACL abuse paths evaluated"),
                            item("Path to domain administration documented", "Each step with evidence."),
                        ]),
                        PlanPhase(name: "Domain dominance checks", summary: "What would a real attacker get.", items: [
                            item("Backup and recovery exposure assessed"),
                            item("Detection and response observed", "Did anyone notice? Note timestamps for the report."),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Web application",
                     summary: "One application, every role, OWASP-aligned.",
                     fields: standardFields + [PlanField(label: "Application URL"), PlanField(label: "Roles tested", kind: .multiline), PlanField(label: "Authenticated testing", kind: .toggle)],
                     phases: [
                        preparation,
                        PlanPhase(name: "Mapping", summary: "Know the application before testing it.", items: [
                            item("Functionality and roles mapped", "Every page, API and role; what each role should and should not be able to do."),
                            item("Technology stack identified"),
                            item("Entry points and parameters listed"),
                        ]),
                        PlanPhase(name: "Authentication and session management", items: [
                            item("Login, registration and password reset flows"),
                            item("Multi-factor and account lockout behaviour"),
                            item("Session token properties and lifecycle"),
                        ]),
                        PlanPhase(name: "Authorization", items: [
                            item("Horizontal access between users of the same role"),
                            item("Vertical access between roles"),
                            item("Direct object references on every identifier"),
                        ]),
                        PlanPhase(name: "Input handling", items: [
                            item("Injection in every parameter type", "Database, command, template, LDAP, path."),
                            item("Cross-site scripting (stored, reflected, DOM)"),
                            item("File upload and download handling"),
                            item("Server-side request forgery and redirects"),
                        ]),
                        PlanPhase(name: "Business logic and client side", items: [
                            item("Workflow and state manipulation"),
                            item("Rate limiting and abuse of functionality"),
                            item("Client-side controls and sensitive data in the browser"),
                        ]),
                        PlanPhase(name: "Configuration", items: [
                            item("Security headers and cookie flags"),
                            item("TLS configuration"),
                            item("Error handling and information disclosure"),
                            item("Dependencies and known vulnerabilities"),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Minimal plan",
                     summary: "A short plan to shape into your own — add phases and items, then save it as a template.",
                     fields: [PlanField(label: "Client"), PlanField(label: "Scope", kind: .multiline), PlanField(label: "Start date", kind: .date)],
                     phases: [
                        PlanPhase(name: "Preparation", items: [item("Scope and rules of engagement confirmed")]),
                        PlanPhase(name: "Execution", items: [item("Reconnaissance"), item("Enumeration"), item("Vulnerability analysis"), item("Exploitation within the RoE")]),
                        PlanPhase(name: "Reporting", items: [item("Findings and evidence complete"), item("Debrief held")]),
                     ], builtIn: true),
    ]
}
