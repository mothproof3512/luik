import AppKit
import Foundation
import Observation
import SwiftUI

/// One response in the redirect chain.
struct HTTPHop: Identifiable {
    let id = UUID()
    var url: URL
    var status: Int
    var headers: [(name: String, value: String)]
    var bodyBytes: Int

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    func headerValues(_ name: String) -> [String] {
        headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { $0.value }
    }
}

struct HTTPHeadersResult {
    var url: URL
    var checkedAt: Date
    var hops: [HTTPHop] = []
    var items: [CheckItem] = []
    var error: String?

    var final: HTTPHop? { hops.last }
    var problems: [CheckItem] { items.filter { $0.level == .warn || $0.level == .fail } }
}

/// GET one URL, follow redirects by hand (so every hop is visible), and judge the response
/// headers: HSTS, CSP, frame options, content-type sniffing, referrer and permissions policies,
/// cookie flags, CORS and version disclosure. One request per hop; certificates are not
/// verified (the TLS inspector does that), and nothing is submitted.
@Observable
final class HTTPHeadersCheck: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = HTTPHeadersCheck()

    var url = ""
    var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    var isRunning = false
    var result: HTTPHeadersResult?
    var error: String?

    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func run() {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let start = URL(string: text), let host = start.host, !host.isEmpty else {
            error = "Enter a URL, e.g. https://www.example.com/login."
            return
        }
        isRunning = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.fetch(start)
            DispatchQueue.main.async {
                self.result = result
                self.isRunning = false
                self.error = result.error
                ActivityLog.shared.record(.action, "HTTP headers checked for \(start.absoluteString): \(result.problems.count) issue(s), \(result.hops.count) hop(s)", source: "Tools", host: host)
            }
        }
    }

    // Accept any certificate: the headers are the subject here, the TLS inspector judges the certificate.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // Do not follow redirects: each hop is recorded and requested again by hand.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    private func fetch(_ start: URL) -> HTTPHeadersResult {
        var result = HTTPHeadersResult(url: start, checkedAt: Date())
        var current = start
        for _ in 0..<10 {
            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let semaphore = DispatchSemaphore(value: 0)
            var data: Data?
            var response: HTTPURLResponse?
            var failure: Error?
            let task = session.dataTask(with: request) { d, r, e in
                data = d
                response = r as? HTTPURLResponse
                failure = e
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 15)
            guard let response else {
                result.error = "No response from \(current.absoluteString): \(failure?.localizedDescription ?? "timeout")"
                break
            }
            var headers: [(name: String, value: String)] = []
            for (key, value) in response.allHeaderFields {
                headers.append((name: String(describing: key), value: String(describing: value)))
            }
            headers.sort { $0.name.lowercased() < $1.name.lowercased() }
            let hop = HTTPHop(url: current, status: response.statusCode, headers: headers, bodyBytes: data?.count ?? 0)
            result.hops.append(hop)
            if (300...399).contains(response.statusCode), let location = hop.header("Location"), let next = URL(string: location, relativeTo: current)?.absoluteURL {
                if result.hops.count >= 10 { break }
                current = next
                continue
            }
            break
        }
        result.items = HTTPHeadersCheck.judge(result)
        return result
    }

    // MARK: - The verdict

    static func judge(_ result: HTTPHeadersResult) -> [CheckItem] {
        var items: [CheckItem] = []
        guard let final = result.final else { return items }
        let isHTTPS = final.url.scheme?.lowercased() == "https"

        // Redirects
        if result.hops.count > 1 {
            let chain = result.hops.map { "\($0.status) \($0.url.absoluteString)" }.joined(separator: " → ")
            items.append(CheckItem(level: .info, text: "Redirect chain (\(result.hops.count - 1)): \(chain)"))
        }
        if result.url.scheme?.lowercased() == "http" {
            if isHTTPS {
                items.append(CheckItem(level: .pass, text: "Plain HTTP redirects to HTTPS."))
            } else {
                items.append(CheckItem(level: .fail, text: "Plain HTTP is served without a redirect to HTTPS."))
            }
        }
        items.append(CheckItem(level: final.status >= 500 ? .warn : .info, text: "Final response: HTTP \(final.status), \(final.bodyBytes) bytes\(final.header("Content-Type").map { ", \($0)" } ?? "")."))

        // HSTS
        if isHTTPS {
            if let hsts = final.header("Strict-Transport-Security") {
                let lower = hsts.lowercased().replacingOccurrences(of: " ", with: "")
                let maxAge = lower.components(separatedBy: ";").first { $0.hasPrefix("max-age=") }.flatMap { Int($0.dropFirst(8)) } ?? 0
                if maxAge < 15_552_000 {
                    items.append(CheckItem(level: .warn, text: "HSTS max-age is \(maxAge) s (\(maxAge / 86400) days) — at least 180 days (15552000) is recommended, a year for preload."))
                } else {
                    items.append(CheckItem(level: .pass, text: "HSTS: \(hsts)\(lower.contains("includesubdomains") ? "" : " (no includeSubDomains)")."))
                }
            } else {
                items.append(CheckItem(level: .warn, text: "No Strict-Transport-Security header: first visits and typed http:// links can be intercepted and downgraded."))
            }
        }

        // CSP
        let csp = final.headerValues("Content-Security-Policy")
        let cspReportOnly = final.header("Content-Security-Policy-Report-Only")
        let contentType = final.header("Content-Type")?.lowercased() ?? ""
        let isHTML = contentType.contains("html") || contentType.isEmpty
        var cspFrameAncestors = false
        if let policy = csp.first {
            let lower = policy.lowercased()
            cspFrameAncestors = lower.contains("frame-ancestors")
            var notes: [String] = []
            if lower.contains("'unsafe-inline'") && !lower.contains("nonce-") && !lower.contains("sha256-") { notes.append("'unsafe-inline' without nonces/hashes") }
            if lower.contains("'unsafe-eval'") { notes.append("'unsafe-eval'") }
            if lower.range(of: #"(default|script)-src[^;]*(\s\*|\s\*;|\shttps?:(\s|;|$))"#, options: .regularExpression) != nil { notes.append("wildcard or scheme-only source for scripts") }
            if !lower.contains("default-src") && !lower.contains("script-src") { notes.append("no default-src/script-src") }
            if notes.isEmpty {
                items.append(CheckItem(level: .pass, text: "Content-Security-Policy present\(cspFrameAncestors ? ", with frame-ancestors" : "")."))
            } else {
                items.append(CheckItem(level: .warn, text: "Content-Security-Policy is weak: \(notes.joined(separator: "; ")) — it does little against injected scripts."))
            }
            if csp.count > 1 { items.append(CheckItem(level: .info, text: "\(csp.count) CSP headers — browsers enforce the intersection.")) }
        } else if cspReportOnly != nil {
            items.append(CheckItem(level: .warn, text: "Content-Security-Policy only in Report-Only mode: nothing is blocked."))
        } else if isHTML {
            items.append(CheckItem(level: .warn, text: "No Content-Security-Policy: injected scripts (XSS) run without restriction."))
        }

        // Clickjacking
        if let xfo = final.header("X-Frame-Options") {
            let lower = xfo.lowercased()
            if lower.contains("deny") || lower.contains("sameorigin") {
                items.append(CheckItem(level: .pass, text: "X-Frame-Options: \(xfo)."))
            } else {
                items.append(CheckItem(level: .warn, text: "X-Frame-Options has an unsupported value (\(xfo)) — ALLOW-FROM is ignored by browsers; use CSP frame-ancestors."))
            }
        } else if cspFrameAncestors {
            items.append(CheckItem(level: .pass, text: "Framing restricted by CSP frame-ancestors (no X-Frame-Options needed)."))
        } else if isHTML {
            items.append(CheckItem(level: .warn, text: "No X-Frame-Options and no CSP frame-ancestors: the page can be framed (clickjacking)."))
        }

        // Sniffing, referrer, permissions
        if let nosniff = final.header("X-Content-Type-Options"), nosniff.lowercased().contains("nosniff") {
            items.append(CheckItem(level: .pass, text: "X-Content-Type-Options: nosniff."))
        } else {
            items.append(CheckItem(level: .warn, text: "No X-Content-Type-Options: nosniff — browsers may sniff content types (MIME confusion)."))
        }
        if let referrer = final.header("Referrer-Policy") {
            let lower = referrer.lowercased()
            if lower.contains("unsafe-url") || lower == "no-referrer-when-downgrade" {
                items.append(CheckItem(level: .warn, text: "Referrer-Policy \(referrer) leaks full URLs to other sites."))
            } else {
                items.append(CheckItem(level: .pass, text: "Referrer-Policy: \(referrer)."))
            }
        } else if isHTML {
            items.append(CheckItem(level: .info, text: "No Referrer-Policy header (browser default strict-origin-when-cross-origin applies)."))
        }
        if final.header("Permissions-Policy") == nil && isHTML {
            items.append(CheckItem(level: .info, text: "No Permissions-Policy header (camera, microphone, geolocation … not restricted for embedded content)."))
        }
        if let xss = final.header("X-XSS-Protection"), xss.hasPrefix("1") {
            items.append(CheckItem(level: .info, text: "X-XSS-Protection: \(xss) — obsolete; modern browsers ignore it and the filter introduced issues of its own. Prefer CSP."))
        }

        // Cookies
        let cookies = final.headerValues("Set-Cookie").flatMap { splitCookies($0) }
        for cookie in cookies {
            let name = cookie.split(separator: "=").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "cookie"
            let lower = cookie.lowercased()
            var missing: [String] = []
            if isHTTPS && !lower.contains("secure") { missing.append("Secure") }
            if !lower.contains("httponly") { missing.append("HttpOnly") }
            if !lower.contains("samesite") { missing.append("SameSite") }
            if missing.isEmpty {
                items.append(CheckItem(level: .pass, text: "Cookie \(name): Secure, HttpOnly, SameSite set."))
            } else {
                let sessionLike = ["sess", "sid", "auth", "token", "jwt", "login"].contains { name.lowercased().contains($0) }
                items.append(CheckItem(level: sessionLike ? .fail : .warn, text: "Cookie \(name) lacks \(missing.joined(separator: ", "))\(sessionLike ? " — looks like a session cookie" : "")."))
            }
        }

        // CORS
        if let origin = final.header("Access-Control-Allow-Origin") {
            let credentials = final.header("Access-Control-Allow-Credentials")?.lowercased() == "true"
            if origin == "*" {
                items.append(CheckItem(level: credentials ? .fail : .info, text: "CORS allows any origin (*)\(credentials ? " with credentials — browsers reject that combination, but it signals a reflected-origin setup worth testing" : " — fine for public, unauthenticated content only")."))
            } else {
                items.append(CheckItem(level: .info, text: "CORS: Access-Control-Allow-Origin \(origin)\(credentials ? ", credentials allowed" : "") — test whether the origin is reflected."))
            }
        }

        // Disclosure
        var disclosed: [String] = []
        for name in ["Server", "X-Powered-By", "X-AspNet-Version", "X-AspNetMvc-Version", "X-Generator", "X-Drupal-Cache", "X-Backend-Server"] {
            if let value = final.header(name), value.contains(where: { $0.isNumber }) || name != "Server" {
                disclosed.append("\(name): \(value)")
            }
        }
        if !disclosed.isEmpty {
            items.append(CheckItem(level: .info, text: "Version / technology disclosure: \(disclosed.joined(separator: "; ")) — feed it to the Version check."))
        }
        if let cache = final.header("Cache-Control")?.lowercased(), isHTML, cookies.isEmpty == false, !cache.contains("no-store") {
            items.append(CheckItem(level: .info, text: "Cache-Control “\(cache)” on a response that sets cookies — authenticated pages should be no-store."))
        }
        return items.sorted { $0.level.rawValue > $1.level.rawValue }
    }

    /// URLSession joins several Set-Cookie headers with ", "; split them again on ", <name>=" boundaries.
    static func splitCookies(_ joined: String) -> [String] {
        var cookies: [String] = []
        var current = ""
        let parts = joined.components(separatedBy: ", ")
        for part in parts {
            if current.isEmpty { current = part; continue }
            // A new cookie starts with name= and no spaces before the =; an Expires date does not.
            if let equals = part.firstIndex(of: "="), !part[..<equals].contains(" "), !part.lowercased().hasPrefix("expires") , !part[..<equals].contains(";") {
                cookies.append(current)
                current = part
            } else {
                current += ", " + part
            }
        }
        if !current.isEmpty { cookies.append(current) }
        return cookies
    }

    static func markdown(_ result: HTTPHeadersResult) -> String {
        var out = "## HTTP headers — \(result.url.absoluteString)\n\n_Checked \(result.checkedAt.formatted(date: .abbreviated, time: .shortened))_\n\n"
        out += ShellTool.markdownList(result.items) + "\n\n"
        for hop in result.hops {
            out += "**\(hop.status) \(hop.url.absoluteString)**\n\n```\n"
            for header in hop.headers { out += "\(header.name): \(header.value)\n" }
            out += "```\n\n"
        }
        return out
    }
}

struct HTTPHeadersView: View {
    @Environment(FindingsStore.self) private var findings
    @Environment(TargetStore.self) private var targets
    @Environment(UIState.self) private var ui
    @State private var showHeaders = true

    var body: some View {
        @Bindable var check = HTTPHeadersCheck.shared
        VStack(spacing: 0) {
            CheckToolbar(text: $check.url, placeholder: "URL (https://www.example.com/login)", isRunning: check.isRunning, hasOptions: true, optionsHelp: "User-Agent", run: { check.run() }) {
                Text("User-Agent").font(.caption.weight(.semibold))
                TextField("User-Agent header", text: $check.userAgent)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            } trailing: {
                if let result = check.result, result.final != nil {
                    CheckResultButtons(markdown: { HTTPHeadersCheck.markdown(result) },
                                       findingTitle: result.problems.isEmpty ? nil : "Missing or weak security headers on \(result.url.host ?? "")",
                                       createFinding: { createFinding(result) },
                                       addToTargets: { addToTargets(result) })
                }
            }
            Divider()
            if let error = check.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if let result = check.result, let final = result.final {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(result.url.host ?? result.url.absoluteString)
                                .font(.title2.weight(.semibold))
                            Text("HTTP \(final.status) · \(result.problems.filter { $0.level == .fail }.count) failing · \(result.problems.filter { $0.level == .warn }.count) warnings · \(result.hops.count) hop(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.items) { CheckItemRow(item: $0) }
                        DisclosureGroup(isExpanded: $showHeaders) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.hops) { hop in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(hop.status) \(hop.url.absoluteString)")
                                            .font(.caption.weight(.semibold))
                                        ForEach(Array(hop.headers.enumerated()), id: \.offset) { _, header in
                                            Text("\(header.name): \(header.value)")
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Response headers per hop")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if check.error == nil {
                EmptyState(icon: "list.bullet.rectangle", title: "HTTP headers",
                           message: "One GET per redirect hop, then HSTS, CSP, framing, nosniff, referrer and permissions policies, cookie flags, CORS and version disclosure, judged. Nothing is submitted; certificates are not verified here.")
            }
        }
    }

    private func createFinding(_ result: HTTPHeadersResult) {
        let host = result.url.host ?? result.url.absoluteString
        var finding = Finding(title: "Missing or weak security headers on \(host)")
        let fails = result.problems.filter { $0.level == .fail }
        finding.severity = fails.contains { $0.text.contains("Plain HTTP") || $0.text.contains("session cookie") } ? .medium : .low
        finding.description = "URL: \(result.url.absoluteString)\n\nIssues:\n" + result.problems.map { "- \($0.text)" }.joined(separator: "\n")
        finding.impact = "Without these headers the browser's built-in defences are off: injected scripts run unrestricted, the page can be framed for clickjacking, cookies can be read by scripts or sent over plain HTTP, and first connections can be downgraded."
        finding.recommendation = "Send Strict-Transport-Security (max-age ≥ 15552000; includeSubDomains), a Content-Security-Policy with nonces or hashes and frame-ancestors, X-Content-Type-Options: nosniff, a Referrer-Policy and Permissions-Policy; set Secure, HttpOnly and SameSite on cookies; remove version headers."
        finding.affected = [result.url.absoluteString]
        finding.references = "https://owasp.org/www-project-secure-headers/\nhttps://developer.mozilla.org/docs/Web/HTTP/CSP"
        finding.source = "HTTP headers check"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the HTTP headers check", source: "Tools", host: host)
    }

    private func addToTargets(_ result: HTTPHeadersResult) {
        guard let host = result.url.host else { return }
        let isIP = host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
        let address = isIP ? host : (DNS.a(host).first ?? host)
        let node = targets.addHost(address: address, hostname: isIP ? "" : host)
        let scheme = result.url.scheme?.lowercased() ?? "https"
        let number = result.url.port ?? (scheme == "https" ? 443 : 80)
        let server = result.final?.header("Server") ?? ""
        let port = targets.addPort(to: node, number: number, proto: "tcp", description: "\(scheme == "https" ? "https" : "http")\(server.isEmpty ? "" : " — \(server)")")
        let note = "HTTP headers (\(result.checkedAt.formatted(date: .abbreviated, time: .shortened))) for \(result.url.absoluteString):\n" + result.problems.map { "- \($0.text)" }.joined(separator: "\n") + "\n"
        if !port.notes.contains("HTTP headers (") { port.notes += (port.notes.isEmpty ? "" : "\n") + note }
        targets.scheduleSave()
        ui.flash("\(host):\(number) added to Targets with the header summary.", seconds: 2)
    }
}
