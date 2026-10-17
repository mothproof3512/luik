import Foundation

/// Ready-made starting points: five web application set-ups, five authentication flows and five
/// network layouts. Each template is built on a 240 × 110 grid (column, row) so the drawings share
/// one rhythm; zones are given as grid rectangles too.
struct DiagramTemplate: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case webApp = "Web application set-ups"
        case auth = "Authentication flows"
        case network = "Network layouts"

        var id: String { rawValue }
    }

    let id: String
    let category: Category
    let name: String
    let summary: String
    let build: (String) -> Diagram

    static let all: [DiagramTemplate] = DiagramTemplateCatalog.webApp + DiagramTemplateCatalog.auth + DiagramTemplateCatalog.network

    static func templates(in category: Category) -> [DiagramTemplate] {
        all.filter { $0.category == category }
    }
}

/// Small builder so a template reads as a list of elements instead of coordinates.
private struct TemplateBuilder {
    static let columnWidth = 240.0
    static let rowHeight = 110.0
    static let originX = 120.0
    static let originY = 120.0

    var diagram: Diagram
    private var nodes: [String: UUID] = [:]

    init(name: String) {
        diagram = Diagram(name: name)
    }

    /// Adds a node at grid position (column, row) under a short key for links.
    mutating func node(_ key: String, _ kind: DiagramNodeKind, _ label: String, _ address: String = "", at column: Double, _ row: Double, notes: String = "") {
        let node = DiagramNode(kind: kind, label: label, address: address, notes: notes,
                               x: TemplateBuilder.originX + column * TemplateBuilder.columnWidth,
                               y: TemplateBuilder.originY + row * TemplateBuilder.rowHeight)
        nodes[key] = node.id
        diagram.nodes.append(node)
    }

    mutating func link(_ from: String, _ to: String, _ label: String = "", style: DiagramLinkStyle = .solid, directed: Bool = false) {
        guard let a = nodes[from], let b = nodes[to] else { return }
        diagram.links.append(DiagramLink(from: a, to: b, label: label, style: style, directed: directed))
    }

    /// A zone spanning grid columns c0…c1 and rows r0…r1 (inclusive), with a little margin.
    mutating func zone(_ name: String, columns c0: Double, _ c1: Double, rows r0: Double, _ r1: Double, color: String) {
        let x = TemplateBuilder.originX + c0 * TemplateBuilder.columnWidth - DiagramMetrics.nodeWidth / 2 - 20
        let y = TemplateBuilder.originY + r0 * TemplateBuilder.rowHeight - DiagramMetrics.nodeHeight / 2 - DiagramMetrics.zoneHeaderHeight - 12
        let width = (c1 - c0) * TemplateBuilder.columnWidth + DiagramMetrics.nodeWidth + 40
        let height = (r1 - r0) * TemplateBuilder.rowHeight + DiagramMetrics.nodeHeight + DiagramMetrics.zoneHeaderHeight + 24
        diagram.zones.append(DiagramZone(name: name, x: x, y: y, width: width, height: height, colorHex: color))
    }
}

private enum Palette {
    static let edge = "#F2994A"
    static let app = "#E07A5F"
    static let data = "#27AE60"
    static let identity = "#BB6BD9"
    static let net = "#2F80ED"
    static let dmz = "#F2994A"
    static let cloud = "#3E9BE8"
    static let client = "#22B5A6"
    static let mgmt = "#8A8F98"
    static let ot = "#E5484D"
}

enum DiagramTemplateCatalog {
    // MARK: - Web application set-ups

    static let webApp: [DiagramTemplate] = [
        DiagramTemplate(id: "web-three-tier", category: .webApp, name: "Classic three-tier",
                        summary: "Load balancer, two web servers, application servers and a database — the on-premises standard.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "Users", "browser", at: 0, 1)
            b.node("fw", .firewall, "Firewall", at: 1, 1)
            b.node("lb", .loadBalancer, "Load balancer", "www.example.com", at: 2, 1)
            b.node("web1", .webServer, "Web 1", "10.0.1.11", at: 3, 0)
            b.node("web2", .webServer, "Web 2", "10.0.1.12", at: 3, 2)
            b.node("app1", .server, "App 1", "10.0.2.21", at: 4, 0)
            b.node("app2", .server, "App 2", "10.0.2.22", at: 4, 2)
            b.node("db", .database, "Database", "10.0.3.31", at: 5, 1)
            b.node("dbr", .database, "DB replica", "10.0.3.32", at: 6, 1)
            b.link("user", "fw", "443"); b.link("fw", "lb")
            b.link("lb", "web1"); b.link("lb", "web2")
            b.link("web1", "app1"); b.link("web1", "app2"); b.link("web2", "app1"); b.link("web2", "app2")
            b.link("app1", "db"); b.link("app2", "db"); b.link("db", "dbr", "replication", style: .dashed, directed: true)
            b.zone("Web tier", columns: 3, 3, rows: 0, 2, color: Palette.edge)
            b.zone("Application tier", columns: 4, 4, rows: 0, 2, color: Palette.app)
            b.zone("Data tier", columns: 5, 6, rows: 1, 1, color: Palette.data)
            return b.diagram
        },
        DiagramTemplate(id: "web-spa-api", category: .webApp, name: "SPA + REST API",
                        summary: "Static frontend from a CDN, API behind a gateway with JWT, database, cache and object storage.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "User", "browser / mobile", at: 0, 1)
            b.node("cdn", .cdn, "CDN", "static assets", at: 1, 0)
            b.node("waf", .waf, "WAF", "api.example.com", at: 1, 2)
            b.node("spa", .webApp, "SPA", "app.example.com", at: 2, 0)
            b.node("gw", .reverseProxy, "API gateway", "rate limit, JWT check", at: 2, 2)
            b.node("api", .api, "REST API", "v1", at: 3, 2)
            b.node("idp", .authorizationServer, "Auth server", "OIDC", at: 3, 3)
            b.node("db", .database, "Database", at: 4, 1)
            b.node("cache", .cache, "Cache", "Redis", at: 4, 2)
            b.node("s3", .objectStorage, "Uploads", "bucket", at: 4, 3)
            b.link("user", "cdn", "443"); b.link("cdn", "spa")
            b.link("user", "waf", "443"); b.link("waf", "gw"); b.link("gw", "api", "bearer", directed: true)
            b.link("user", "idp", "login", style: .dotted, directed: true); b.link("gw", "idp", "JWKS", style: .dotted)
            b.link("api", "db"); b.link("api", "cache"); b.link("api", "s3"); b.link("user", "s3", "presigned URL", style: .dashed)
            b.zone("Edge", columns: 1, 1, rows: 0, 2, color: Palette.edge)
            b.zone("Application", columns: 2, 3, rows: 0, 3, color: Palette.app)
            b.zone("Data", columns: 4, 4, rows: 1, 3, color: Palette.data)
            return b.diagram
        },
        DiagramTemplate(id: "web-microservices", category: .webApp, name: "Microservices on Kubernetes",
                        summary: "Ingress, several services with their own databases, a message bus and a service for background work.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "Users", at: 0, 1)
            b.node("waf", .waf, "WAF / LB", at: 1, 1)
            b.node("ingress", .reverseProxy, "Ingress", "nginx / Traefik", at: 2, 1)
            b.node("auth", .microservice, "auth-svc", at: 3, 0)
            b.node("orders", .microservice, "orders-svc", at: 3, 1)
            b.node("catalog", .microservice, "catalog-svc", at: 3, 2)
            b.node("bus", .messageQueue, "Message bus", "Kafka", at: 4, 1)
            b.node("worker", .microservice, "notify-worker", at: 5, 1)
            b.node("authdb", .database, "users db", at: 4, 0)
            b.node("ordersdb", .database, "orders db", at: 4, 2)
            b.node("catalogdb", .database, "catalog db", at: 4, 3)
            b.node("vault", .secretsVault, "Secrets", "Vault / KMS", at: 5, 0)
            b.node("k8s", .container, "Cluster", "k8s API 6443", at: 5, 3)
            b.node("mail", .thirdParty, "E-mail provider", at: 6, 1)
            b.link("user", "waf", "443"); b.link("waf", "ingress")
            b.link("ingress", "auth"); b.link("ingress", "orders"); b.link("ingress", "catalog")
            b.link("auth", "authdb"); b.link("orders", "ordersdb"); b.link("catalog", "catalogdb")
            b.link("orders", "bus", "events", directed: true); b.link("bus", "worker", directed: true); b.link("worker", "mail")
            b.link("auth", "vault", style: .dotted); b.link("orders", "vault", style: .dotted)
            b.zone("Cluster", columns: 2, 5, rows: 0, 3, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "web-serverless", category: .webApp, name: "Serverless",
                        summary: "CDN-hosted frontend, API gateway in front of functions, managed database, queue and storage.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "User", at: 0, 1)
            b.node("cdn", .cdn, "CDN", "CloudFront / Front Door", at: 1, 0)
            b.node("spa", .webApp, "Frontend", "static site", at: 2, 0)
            b.node("gw", .reverseProxy, "API gateway", "managed", at: 1, 2)
            b.node("fn1", .serverless, "GET /items", "function", at: 2, 2)
            b.node("fn2", .serverless, "POST /orders", "function", at: 2, 3)
            b.node("idp", .identityProvider, "Cognito / Entra", "user pool", at: 1, 3)
            b.node("db", .database, "Managed DB", "DynamoDB / Cosmos", at: 3, 2)
            b.node("queue", .messageQueue, "Queue", "SQS / Service Bus", at: 3, 3)
            b.node("fn3", .serverless, "process-order", "function", at: 4, 3)
            b.node("s3", .objectStorage, "Storage", "bucket", at: 4, 2)
            b.node("kv", .secretsVault, "Secrets manager", at: 3, 1)
            b.link("user", "cdn", "443"); b.link("cdn", "spa"); b.link("user", "gw", "443")
            b.link("gw", "idp", "authorizer", style: .dotted); b.link("gw", "fn1"); b.link("gw", "fn2")
            b.link("fn1", "db"); b.link("fn2", "db"); b.link("fn2", "queue", directed: true); b.link("queue", "fn3", directed: true)
            b.link("fn3", "s3"); b.link("fn1", "kv", style: .dotted); b.link("fn2", "kv", style: .dotted)
            b.zone("Cloud account", columns: 1, 4, rows: 0, 3, color: Palette.cloud)
            return b.diagram
        },
        DiagramTemplate(id: "web-monolith", category: .webApp, name: "Monolith with CMS / webshop",
                        summary: "Reverse proxy and WAF in front of one application with database, file storage, payment provider and mail.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "Customers", at: 0, 1)
            b.node("admin", .workstation, "Admin", "/admin", at: 0, 2)
            b.node("waf", .waf, "WAF", at: 1, 1)
            b.node("proxy", .reverseProxy, "Reverse proxy", "nginx, TLS", at: 2, 1)
            b.node("app", .webApp, "Application", "PHP / .NET / Java", at: 3, 1)
            b.node("db", .database, "Database", "MySQL", at: 4, 0)
            b.node("files", .objectStorage, "Media / uploads", "NFS or bucket", at: 4, 1)
            b.node("search", .microservice, "Search", "Elasticsearch", at: 4, 2)
            b.node("psp", .thirdParty, "Payment provider", "webhooks", at: 5, 0)
            b.node("mail", .mailServer, "Mail relay", "587", at: 5, 2)
            b.node("backup", .server, "Backups", at: 5, 1)
            b.link("user", "waf", "443"); b.link("admin", "waf", "443"); b.link("waf", "proxy"); b.link("proxy", "app")
            b.link("app", "db"); b.link("app", "files"); b.link("app", "search")
            b.link("app", "psp", "redirect + webhook", style: .dashed); b.link("app", "mail"); b.link("db", "backup", style: .dotted)
            b.zone("DMZ", columns: 1, 2, rows: 1, 1, color: Palette.dmz)
            b.zone("Application", columns: 3, 4, rows: 0, 2, color: Palette.app)
            return b.diagram
        },
    ]

    // MARK: - Authentication flows

    static let auth: [DiagramTemplate] = [
        DiagramTemplate(id: "auth-oauth-pkce", category: .auth, name: "OAuth 2.0 authorization code + PKCE",
                        summary: "Public client (SPA / mobile) → authorization server → tokens → API with JWT validation.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "User", at: 0, 1)
            b.node("client", .webApp, "SPA / mobile app", "public client", at: 1, 1)
            b.node("as", .authorizationServer, "Authorization server", "/authorize, /token", at: 3, 0)
            b.node("mfa", .mfa, "MFA", at: 4, 0)
            b.node("dir", .directory, "User store", at: 5, 0)
            b.node("api", .api, "Resource server (API)", "validates JWT", at: 3, 2)
            b.node("jwks", .sessionStore, "JWKS / keys", "/.well-known", at: 4, 2)
            b.link("user", "client")
            b.link("client", "as", "1. authorize + code_challenge", style: .dotted, directed: true)
            b.link("as", "mfa", "2. login + MFA"); b.link("as", "dir")
            b.link("as", "client", "3. redirect with code", style: .dotted, directed: true)
            b.link("client", "as", "4. /token + code_verifier", directed: true)
            b.link("client", "api", "5. Bearer access token", directed: true)
            b.link("api", "jwks", "signature check", style: .dotted)
            b.zone("Identity", columns: 3, 5, rows: 0, 0, color: Palette.identity)
            b.zone("Resources", columns: 3, 4, rows: 2, 2, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "auth-sso-saml-oidc", category: .auth, name: "Enterprise SSO (SAML / OIDC)",
                        summary: "Corporate IdP with MFA federating several SaaS and internal applications; directory behind it.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "Employee", "browser", at: 0, 1)
            b.node("idp", .identityProvider, "Corporate IdP", "Entra / Okta / ADFS", at: 2, 1)
            b.node("mfa", .mfa, "MFA", "push / FIDO2", at: 2, 2)
            b.node("ad", .domainController, "Active Directory", "sync", at: 2, 0)
            b.node("hr", .thirdParty, "HR system", "SCIM provisioning", at: 3, 0)
            b.node("saas1", .cloud, "SaaS app A", "SAML SP", at: 4, 0)
            b.node("saas2", .cloud, "SaaS app B", "OIDC RP", at: 4, 1)
            b.node("intranet", .webApp, "Internal portal", "OIDC RP", at: 4, 2)
            b.node("legacy", .webServer, "Legacy app", "header-based via proxy", at: 5, 2)
            b.node("proxy", .reverseProxy, "Auth proxy", at: 4, 3)
            b.link("user", "idp", "login", style: .dotted, directed: true); b.link("idp", "mfa"); b.link("idp", "ad")
            b.link("hr", "idp", "SCIM", style: .dashed, directed: true)
            b.link("idp", "saas1", "SAML assertion", directed: true); b.link("idp", "saas2", "ID token", directed: true); b.link("idp", "intranet", "ID token", directed: true)
            b.link("user", "proxy"); b.link("proxy", "idp", "OIDC", style: .dotted); b.link("proxy", "legacy", "X-User header", directed: true)
            b.zone("Identity", columns: 2, 3, rows: 0, 2, color: Palette.identity)
            b.zone("Applications", columns: 4, 5, rows: 0, 3, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "auth-session", category: .auth, name: "Session-based login",
                        summary: "Classic form login: password hashes in the database, server-side sessions, cookie back to the browser.") { name in
            var b = TemplateBuilder(name: name)
            b.node("user", .user, "User", "browser", at: 0, 1)
            b.node("waf", .waf, "WAF / rate limit", at: 1, 1)
            b.node("app", .webApp, "Web application", "/login, /logout", at: 2, 1)
            b.node("sess", .sessionStore, "Session store", "Redis, TTL", at: 3, 0)
            b.node("db", .database, "Users table", "bcrypt / argon2 hashes", at: 3, 2)
            b.node("mail", .mailServer, "Mail", "reset links", at: 3, 1)
            b.node("mfa", .mfa, "TOTP", "optional", at: 2, 2)
            b.link("user", "waf", "POST /login"); b.link("waf", "app")
            b.link("app", "db", "verify hash"); b.link("app", "sess", "create session", directed: true)
            b.link("app", "user", "Set-Cookie: HttpOnly; Secure; SameSite", style: .dotted, directed: true)
            b.link("app", "mail", "password reset", style: .dashed); b.link("app", "mfa", style: .dotted)
            b.zone("Application", columns: 2, 3, rows: 0, 2, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "auth-m2m", category: .auth, name: "Machine-to-machine (client credentials / API keys)",
                        summary: "Services and partners calling an API with client credentials or API keys through a gateway, secrets in a vault.") { name in
            var b = TemplateBuilder(name: name)
            b.node("partner", .thirdParty, "Partner system", "API key", at: 0, 0)
            b.node("svc", .microservice, "Internal service", "client_credentials", at: 0, 2)
            b.node("batch", .server, "Batch job", "service account", at: 0, 3)
            b.node("gw", .reverseProxy, "API gateway", "key check, quotas", at: 2, 1)
            b.node("as", .authorizationServer, "Token endpoint", "/token", at: 2, 3)
            b.node("vault", .secretsVault, "Secrets vault", "client secrets, keys", at: 1, 3)
            b.node("api", .api, "API", at: 3, 1)
            b.node("audit", .objectStorage, "Audit log", at: 4, 1)
            b.link("partner", "gw", "X-API-Key", directed: true)
            b.link("svc", "as", "client_id + secret → token", directed: true); b.link("batch", "as", directed: true)
            b.link("svc", "gw", "Bearer", directed: true); b.link("batch", "gw", "Bearer", directed: true)
            b.link("svc", "vault", style: .dotted); b.link("batch", "vault", style: .dotted); b.link("as", "vault", style: .dotted)
            b.link("gw", "as", "introspection", style: .dotted); b.link("gw", "api"); b.link("api", "audit", style: .dashed)
            b.zone("Callers", columns: 0, 0, rows: 0, 3, color: Palette.client)
            b.zone("Platform", columns: 1, 4, rows: 1, 3, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "auth-kerberos", category: .auth, name: "Active Directory (Kerberos / NTLM)",
                        summary: "Workstation logon against the domain controller, tickets for file and web servers, ADFS for federation.") { name in
            var b = TemplateBuilder(name: name)
            b.node("ws", .workstation, "Workstation", "domain-joined", at: 0, 1)
            b.node("dc", .domainController, "DC / KDC", "88, 389, 445", at: 2, 1)
            b.node("dc2", .domainController, "DC02", "replica", at: 2, 2)
            b.node("file", .server, "File server", "CIFS/SPN", at: 4, 0)
            b.node("web", .webServer, "Intranet web", "HTTP/SPN, Negotiate", at: 4, 1)
            b.node("sql", .database, "SQL Server", "MSSQLSvc SPN", at: 4, 2)
            b.node("adfs", .identityProvider, "ADFS / Entra Connect", "federation", at: 2, 3)
            b.node("cloud", .cloud, "Microsoft 365", at: 4, 3)
            b.node("ca", .certificateAuthority, "AD CS", "PKI", at: 2, 0)
            b.link("ws", "dc", "AS-REQ / TGT", directed: true); b.link("dc", "dc2", "replication", style: .dashed)
            b.link("ws", "file", "service ticket", directed: true); b.link("ws", "web", "Negotiate", directed: true); b.link("ws", "sql", "integrated auth", directed: true)
            b.link("file", "dc", style: .dotted); b.link("web", "dc", style: .dotted); b.link("sql", "dc", style: .dotted)
            b.link("dc", "adfs"); b.link("adfs", "cloud", "SAML / WS-Fed", directed: true); b.link("ws", "ca", "certificates", style: .dotted)
            b.zone("Domain", columns: 2, 2, rows: 0, 3, color: Palette.identity)
            b.zone("Member servers", columns: 4, 4, rows: 0, 2, color: Palette.net)
            return b.diagram
        },
    ]

    // MARK: - Network layouts

    static let network: [DiagramTemplate] = [
        DiagramTemplate(id: "net-small-office", category: .network, name: "Small office (flat network)",
                        summary: "One ISP router, one switch, servers and clients on the same segment, Wi-Fi and a printer.") { name in
            var b = TemplateBuilder(name: name)
            b.node("inet", .internet, "Internet", at: 0, 1)
            b.node("rtr", .router, "ISP router / FW", "192.168.1.1", at: 1, 1)
            b.node("sw", .switchDevice, "Switch", at: 2, 1)
            b.node("ap", .accessPoint, "Wi-Fi", "same VLAN", at: 3, 0)
            b.node("nas", .server, "NAS / file server", "192.168.1.10", at: 3, 1)
            b.node("prn", .printer, "Printer", "192.168.1.20", at: 3, 2)
            b.node("pc", .workstation, "Workstations", "192.168.1.100-150", at: 4, 1)
            b.node("lt", .laptop, "Laptops", "DHCP", at: 4, 0)
            b.link("inet", "rtr"); b.link("rtr", "sw"); b.link("sw", "ap"); b.link("sw", "nas"); b.link("sw", "prn"); b.link("sw", "pc"); b.link("ap", "lt", style: .dotted)
            b.zone("LAN 192.168.1.0/24", columns: 2, 4, rows: 0, 2, color: Palette.net)
            return b.diagram
        },
        DiagramTemplate(id: "net-dmz", category: .network, name: "DMZ with two firewalls",
                        summary: "Internet → external firewall → DMZ (web, mail relay, VPN) → internal firewall → LAN with servers and clients.") { name in
            var b = TemplateBuilder(name: name)
            b.node("inet", .internet, "Internet", at: 0, 1)
            b.node("fw1", .firewall, "External firewall", "203.0.113.1", at: 1, 1)
            b.node("web", .webServer, "Web / reverse proxy", "172.16.0.10", at: 2, 0)
            b.node("mail", .mailServer, "Mail relay", "172.16.0.20", at: 2, 1)
            b.node("vpn", .vpn, "VPN gateway", "172.16.0.30", at: 2, 2)
            b.node("fw2", .firewall, "Internal firewall", at: 3, 1)
            b.node("core", .switchDevice, "Core switch", at: 4, 1)
            b.node("dc", .domainController, "DC01", "10.0.0.10", at: 5, 0)
            b.node("app", .server, "App server", "10.0.0.20", at: 5, 1)
            b.node("db", .database, "SQL01", "10.0.0.30", at: 5, 2)
            b.node("pc", .workstation, "Clients", "10.0.20.0/24", at: 6, 1)
            b.link("inet", "fw1"); b.link("fw1", "web", "443"); b.link("fw1", "mail", "25"); b.link("fw1", "vpn", "443/UDP 500")
            b.link("web", "fw2"); b.link("mail", "fw2"); b.link("vpn", "fw2"); b.link("fw2", "core")
            b.link("core", "dc"); b.link("core", "app"); b.link("core", "db"); b.link("core", "pc"); b.link("web", "app", "8443", style: .dashed)
            b.zone("DMZ 172.16.0.0/24", columns: 2, 2, rows: 0, 2, color: Palette.dmz)
            b.zone("Internal 10.0.0.0/16", columns: 4, 6, rows: 0, 2, color: Palette.net)
            return b.diagram
        },
        DiagramTemplate(id: "net-segmented", category: .network, name: "Segmented enterprise (VLANs)",
                        summary: "Core firewall between server, client, management, guest Wi-Fi and OT segments.") { name in
            var b = TemplateBuilder(name: name)
            b.node("inet", .internet, "Internet", at: 0, 2)
            b.node("edge", .firewall, "Edge firewall", at: 1, 2)
            b.node("core", .firewall, "Core firewall / L3", "inter-VLAN", at: 2, 2)
            b.node("srv1", .domainController, "DC", "VLAN 10", at: 4, 0)
            b.node("srv2", .server, "Servers", "VLAN 10", at: 5, 0)
            b.node("pc", .workstation, "Workstations", "VLAN 20", at: 4, 1)
            b.node("voip", .mobile, "VoIP / phones", "VLAN 21", at: 5, 1)
            b.node("mgmt", .switchDevice, "Switch mgmt", "VLAN 99", at: 4, 2)
            b.node("jump", .server, "Jump host", "VLAN 99", at: 5, 2)
            b.node("guest", .accessPoint, "Guest Wi-Fi", "VLAN 50, internet only", at: 4, 3)
            b.node("plc", .iot, "PLCs / HMI", "VLAN 200", at: 4, 4)
            b.node("scada", .server, "SCADA server", "VLAN 200", at: 5, 4)
            b.link("inet", "edge"); b.link("edge", "core")
            b.link("core", "srv1"); b.link("core", "pc"); b.link("core", "mgmt"); b.link("core", "guest"); b.link("core", "plc", "allow-list only", style: .dashed)
            b.link("srv1", "srv2"); b.link("pc", "voip", style: .dotted); b.link("mgmt", "jump"); b.link("plc", "scada")
            b.zone("Servers — VLAN 10", columns: 4, 5, rows: 0, 0, color: Palette.net)
            b.zone("Clients — VLAN 20/21", columns: 4, 5, rows: 1, 1, color: Palette.client)
            b.zone("Management — VLAN 99", columns: 4, 5, rows: 2, 2, color: Palette.mgmt)
            b.zone("Guest — VLAN 50", columns: 4, 4, rows: 3, 3, color: Palette.cloud)
            b.zone("OT — VLAN 200", columns: 4, 5, rows: 4, 4, color: Palette.ot)
            return b.diagram
        },
        DiagramTemplate(id: "net-hybrid-cloud", category: .network, name: "Hybrid cloud",
                        summary: "On-premises site connected over VPN / ExpressRoute to a cloud VNet with hub and spoke.") { name in
            var b = TemplateBuilder(name: name)
            b.node("inet", .internet, "Internet", at: 2, 0)
            b.node("fw", .firewall, "Site firewall", "198.51.100.1", at: 1, 1)
            b.node("core", .switchDevice, "Core", at: 0, 1)
            b.node("dc", .domainController, "DC on-prem", "10.1.0.10", at: 0, 0)
            b.node("pc", .workstation, "Clients", "10.1.20.0/24", at: 0, 2)
            b.node("vpn", .vpn, "VPN / ExpressRoute", "site-to-site", at: 2, 1)
            b.node("hubfw", .firewall, "Cloud firewall (hub)", "10.100.0.0/24", at: 3, 1)
            b.node("vm", .server, "VMs (spoke)", "10.101.0.0/24", at: 4, 0)
            b.node("aks", .container, "AKS / EKS (spoke)", "10.102.0.0/22", at: 4, 1)
            b.node("paas", .database, "Managed DB", "private endpoint", at: 4, 2)
            b.node("entra", .identityProvider, "Entra ID / IAM", at: 5, 0)
            b.node("storage", .objectStorage, "Storage", "private endpoint", at: 5, 2)
            b.node("lb", .loadBalancer, "Public LB / App GW", "WAF", at: 3, 0)
            b.link("core", "fw"); b.link("core", "dc"); b.link("core", "pc"); b.link("fw", "vpn"); b.link("vpn", "hubfw", "IPsec", style: .dashed)
            b.link("inet", "lb"); b.link("lb", "hubfw"); b.link("hubfw", "vm"); b.link("hubfw", "aks"); b.link("hubfw", "paas")
            b.link("aks", "paas"); b.link("aks", "storage"); b.link("dc", "entra", "sync", style: .dotted); b.link("vm", "entra", style: .dotted)
            b.zone("On-premises", columns: 0, 1, rows: 0, 2, color: Palette.net)
            b.zone("Cloud — hub", columns: 3, 3, rows: 0, 1, color: Palette.cloud)
            b.zone("Cloud — spokes", columns: 4, 5, rows: 0, 2, color: Palette.app)
            return b.diagram
        },
        DiagramTemplate(id: "net-remote-access", category: .network, name: "Remote access (VPN + jump host)",
                        summary: "Home workers and admins through a VPN gateway with MFA, split into user and admin paths with a jump host.") { name in
            var b = TemplateBuilder(name: name)
            b.node("home", .laptop, "Home workers", "VPN client", at: 0, 0)
            b.node("admin", .laptop, "Admins", "VPN client", at: 0, 2)
            b.node("vendor", .thirdParty, "Vendor", "ZTNA / portal", at: 0, 3)
            b.node("inet", .internet, "Internet", at: 1, 1)
            b.node("vpn", .vpn, "VPN gateway", "443 / UDP 1194", at: 2, 1)
            b.node("mfa", .mfa, "MFA / RADIUS", at: 2, 2)
            b.node("fw", .firewall, "Internal firewall", at: 3, 1)
            b.node("apps", .webServer, "Internal apps", "VLAN 10", at: 4, 0)
            b.node("files", .server, "File server", "VLAN 10", at: 5, 0)
            b.node("jump", .server, "Jump host", "VLAN 99, RDP/SSH", at: 4, 2)
            b.node("pam", .secretsVault, "PAM / vault", "checked-out creds", at: 5, 2)
            b.node("srv", .server, "Servers / network gear", "management", at: 5, 3)
            b.link("home", "inet"); b.link("admin", "inet"); b.link("vendor", "inet"); b.link("inet", "vpn", "TLS"); b.link("vpn", "mfa", style: .dotted)
            b.link("vpn", "fw"); b.link("fw", "apps", "user pool"); b.link("apps", "files"); b.link("fw", "jump", "admin pool"); b.link("jump", "pam", style: .dotted); b.link("jump", "srv", "RDP / SSH", directed: true)
            b.zone("User path", columns: 4, 5, rows: 0, 0, color: Palette.client)
            b.zone("Admin path", columns: 4, 5, rows: 2, 3, color: Palette.mgmt)
            return b.diagram
        },
    ]
}
