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
        PlanTemplate(name: "API assessment",
                     summary: "REST / GraphQL / gRPC APIs: authentication, authorisation per object and function, input handling, rate limits.",
                     fields: standardFields + [
                        PlanField(label: "API style", kind: .choice, options: ["REST", "GraphQL", "gRPC", "SOAP", "Mixed"]),
                        PlanField(label: "Specification received", kind: .choice, options: ["OpenAPI / Swagger", "GraphQL schema", "Postman collection", "None — discovered"]),
                        PlanField(label: "Test accounts per role", kind: .multiline),
                     ],
                     phases: [
                        preparation,
                        PlanPhase(name: "Discovery and mapping", summary: "Every endpoint, parameter and role.", items: [
                            item("Specification reviewed and imported", "Endpoints, methods, parameters, auth requirements; note the undocumented ones you find."),
                            item("Endpoint inventory complete", "Including versions (v1, v2), internal paths, health and debug endpoints."),
                            item("Authentication flows understood", "Tokens, refresh, API keys, sessions; where each is validated."),
                            item("Roles and object ownership mapped", "Which role may read / change which objects — the basis for authorisation tests."),
                            item("Rate limiting and anti-automation observed"),
                        ]),
                        PlanPhase(name: "Authentication and session", summary: "Getting in, staying in.", items: [
                            item("Token handling", "Expiry, revocation, algorithm, signature validation, audience and issuer checks."),
                            item("Credential and key management", "Key rotation, keys in URLs or logs, default keys."),
                            item("Password and MFA flows", "Reset, enrolment, brute-force protection, enumeration."),
                        ]),
                        PlanPhase(name: "Authorisation", summary: "The API's most common failure.", items: [
                            item("Object-level authorisation (BOLA / IDOR)", "Every object id tried with another user's token; predictable ids noted."),
                            item("Function-level authorisation", "Admin and privileged functions with a low-privileged token."),
                            item("Property-level authorisation (mass assignment)", "Extra fields in requests; sensitive fields in responses."),
                        ]),
                        PlanPhase(name: "Input and business logic", summary: "What the server trusts that it should not.", items: [
                            item("Injection per parameter type", "SQL, NoSQL, command, template, LDAP — per data store behind the endpoint."),
                            item("File and content handling", "Uploads, content types, XML, deserialisation."),
                            item("Business logic abuse", "Negative amounts, race conditions, step skipping, replay."),
                            item("Server-side request forgery and open redirects"),
                            item("Error handling and information disclosure", "Stack traces, internal hostnames, verbose errors."),
                        ]),
                        PlanPhase(name: "Infrastructure", summary: "Around the API.", items: [
                            item("TLS configuration and headers"),
                            item("Gateway, WAF and CORS behaviour"),
                            item("Logging and monitoring observed", "Were any of the tests noticed? Note it for the report."),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Cloud configuration review",
                     summary: "Azure / AWS / GCP tenant or account: identity, network exposure, storage, logging — a review with read access, not an attack.",
                     fields: standardFields + [
                        PlanField(label: "Provider", kind: .choice, options: ["Azure / Entra", "AWS", "GCP", "Multi-cloud"]),
                        PlanField(label: "Access provided", kind: .choice, options: ["Reader role", "Security reader", "Audit account", "Exported configuration only"]),
                        PlanField(label: "Subscriptions / accounts in scope", kind: .multiline),
                     ],
                     phases: [
                        preparation,
                        PlanPhase(name: "Inventory", summary: "What exists, and who owns it.", items: [
                            item("Accounts, subscriptions and projects listed"),
                            item("Resource inventory exported", "Compute, storage, databases, functions, networks, identities."),
                            item("Public exposure identified", "Public IPs, load balancers, storage with public access, DNS."),
                        ]),
                        PlanPhase(name: "Identity and access", summary: "Where cloud breaches start.", items: [
                            item("Privileged roles and their holders", "Global admins / account owners; break-glass accounts; MFA on each."),
                            item("Conditional access / IAM policies reviewed", "Least privilege, wildcard permissions, cross-account trusts."),
                            item("Service principals, keys and secrets", "Age, rotation, usage, secrets in code or pipelines."),
                            item("Guest and external identities"),
                        ]),
                        PlanPhase(name: "Network and compute", summary: "Exposure and hardening.", items: [
                            item("Security groups / NSGs / firewall rules", "Management ports open to the internet; overly broad rules."),
                            item("Compute hardening", "Patching, agents, metadata service protection, disk encryption."),
                            item("Private connectivity", "Peering, VPN, private endpoints; flat networks."),
                        ]),
                        PlanPhase(name: "Data and storage", summary: "Where the data is.", items: [
                            item("Storage access and encryption", "Public containers / buckets, shared access signatures, key management."),
                            item("Database exposure and authentication"),
                            item("Backups and retention"),
                        ]),
                        PlanPhase(name: "Logging and monitoring", summary: "Would they notice?", items: [
                            item("Audit logging enabled and retained", "Activity logs, CloudTrail, sign-in logs; retention period."),
                            item("Alerting on privileged actions"),
                            item("Security posture tooling in use", "Defender for Cloud, Security Hub, SCC — findings reviewed."),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Wireless assessment",
                     summary: "Wi-Fi networks of an office or site: encryption, authentication, segmentation, rogue access points.",
                     fields: standardFields + [
                        PlanField(label: "Sites / buildings", kind: .multiline),
                        PlanField(label: "SSIDs in scope", kind: .multiline),
                        PlanField(label: "Client credentials provided", kind: .toggle),
                     ],
                     phases: [
                        preparation,
                        PlanPhase(name: "Survey", summary: "What is in the air.", items: [
                            item("Site survey walked", "Coverage, SSIDs, bands, signal outside the building."),
                            item("Access point and SSID inventory", "Vendor, encryption, authentication type; hidden SSIDs; compare with the client's list."),
                            item("Rogue and neighbouring networks identified", "Unknown APs on the client's premises; evil-twin candidates."),
                        ]),
                        PlanPhase(name: "Authentication and encryption", summary: "Getting on the network.", items: [
                            item("Encryption and protocol versions", "WPA2 / WPA3, PMF, legacy protocols still enabled."),
                            item("Pre-shared key strength and handling", "Within the RoE; where the key is shared and how often it changes."),
                            item("Enterprise authentication (802.1X)", "EAP methods, certificate validation on clients, credential exposure."),
                            item("Captive portal and guest onboarding"),
                        ]),
                        PlanPhase(name: "Post-connection", summary: "What a connected device can reach.", items: [
                            item("Client isolation and segmentation", "Guest to corporate, Wi-Fi to wired, management interfaces reachable?"),
                            item("Internal services reachable from Wi-Fi", "Import discovery results into Targets."),
                            item("Controller and AP management security", "Default credentials, exposed management, firmware."),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Mobile application assessment",
                     summary: "iOS / Android app plus its backend: local storage, transport, authentication, platform protections, API.",
                     fields: standardFields + [
                        PlanField(label: "Platforms", kind: .choice, options: ["iOS", "Android", "Both"]),
                        PlanField(label: "Build provided", kind: .choice, options: ["Store version", "Debug / test build", "Source code"]),
                        PlanField(label: "Backend in scope", kind: .toggle),
                     ],
                     phases: [
                        preparation,
                        PlanPhase(name: "Static analysis", summary: "The package itself.", items: [
                            item("Package information and permissions reviewed", "Entitlements, exported components, deep links, permissions."),
                            item("Secrets and endpoints in the package", "API keys, hard-coded credentials, internal hostnames."),
                            item("Binary protections", "Obfuscation, anti-tampering, debug symbols, jailbreak / root detection."),
                            item("Third-party libraries and versions", "Known vulnerabilities (Version check tool)."),
                        ]),
                        PlanPhase(name: "Local data", summary: "What stays on the device.", items: [
                            item("Local storage of sensitive data", "Databases, preferences, caches, keychain / keystore usage, logs, backups."),
                            item("Screenshots, clipboard and keyboard caching"),
                            item("Biometric and PIN handling"),
                        ]),
                        PlanPhase(name: "Network and backend", summary: "On the wire and behind it.", items: [
                            item("Transport security", "TLS, certificate pinning, cleartext traffic, proxying possible?"),
                            item("Authentication and session handling", "Tokens on device, refresh, logout, re-authentication for sensitive actions."),
                            item("API tested with the API plan", "Authorisation per object and function with the app's tokens."),
                        ]),
                        PlanPhase(name: "Platform interaction", summary: "Where the app meets the OS.", items: [
                            item("Deep links, intents and URL schemes"),
                            item("WebViews and JavaScript bridges"),
                            item("Inter-process communication and exported components"),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Phishing and awareness campaign",
                     summary: "A simulated phishing campaign within the agreed rules: setup, sending, measurement, lessons — never real credential use.",
                     fields: standardFields + [
                        PlanField(label: "Campaign type", kind: .choice, options: ["Credential harvesting (simulated)", "Attachment / link click", "Vishing", "Combined"]),
                        PlanField(label: "Target group size", kind: .text),
                        PlanField(label: "Sending window", kind: .text),
                        PlanField(label: "Works council / HR informed", kind: .toggle),
                     ],
                     phases: [
                        PlanPhase(name: "Preparation", summary: "More agreements than usual.", items: [
                            item("Scope, target group and exclusions agreed", "Who may be targeted, who not; privacy and HR agreements in writing."),
                            item("Scenario and pretext approved by the client", "Realistic but defensible; no fake bad news about people."),
                            item("Infrastructure prepared", "Domain, mail reputation, landing page that records clicks and submissions without storing passwords."),
                            item("Allow-listing arranged where agreed", "So the measurement reflects people, not the mail filter — or deliberately not."),
                            item("Stop criteria and emergency contact agreed"),
                        ]),
                        PlanPhase(name: "Execution", summary: "The campaign itself.", items: [
                            item("Test send to the client contact approved"),
                            item("Campaign sent in waves", "Timing per wave; monitor deliverability and reports to the helpdesk."),
                            item("Reports and reactions tracked", "Who reported, how fast, what the SOC did."),
                            item("Campaign closed and infrastructure taken down"),
                        ]),
                        PlanPhase(name: "Measurement and lessons", summary: "Numbers with context.", items: [
                            item("Metrics compiled", "Delivered, opened, clicked, submitted, reported; per department only if agreed."),
                            item("Technical findings", "Mail filtering, SPF / DKIM / DMARC, link rewriting, reporting button."),
                            item("Awareness recommendations", "Training, reporting process, technical controls."),
                        ]),
                        reporting,
                     ], builtIn: true),
        PlanTemplate(name: "Retest",
                     summary: "Verifying the findings of an earlier report: fixed, partially fixed or still open — nothing new unless agreed.",
                     fields: standardFields + [
                        PlanField(label: "Original report reference", kind: .text),
                        PlanField(label: "Original test date", kind: .date),
                        PlanField(label: "Findings to retest", kind: .multiline),
                        PlanField(label: "New findings allowed", kind: .toggle),
                     ],
                     phases: [
                        PlanPhase(name: "Preparation", summary: "Same scope, same evidence standard.", items: [
                            item("Original findings imported", "Findings tab: the earlier findings with status Open, or a playbook / report export."),
                            item("Scope and access confirmed", "Same accounts and systems as the original test, or the agreed subset."),
                            item("Retest window agreed"),
                        ]),
                        PlanPhase(name: "Verification", summary: "Finding by finding.", items: [
                            item("Each finding reproduced with the original steps", "Evidence captured the same way as before; note the exact command and time."),
                            item("Fixes checked for completeness", "Variants, other hosts with the same issue, bypasses of the fix."),
                            item("Status set per finding", "Resolved, partially fixed (new finding with reduced severity) or still open."),
                            item("Regressions and new exposure noted", "Only reported when the RoE allows new findings."),
                        ]),
                        PlanPhase(name: "Reporting", summary: "Short and comparative.", items: [
                            item("Retest table completed", "Original id, severity, status, evidence reference."),
                            item("Residual risk summarised"),
                            item("Client debrief held"),
                        ]),
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
