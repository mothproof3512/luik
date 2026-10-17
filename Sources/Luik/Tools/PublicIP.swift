import AppKit
import Foundation
import Observation
import SwiftUI

/// Your public (exit) address, asked from a lookup service when you click — never automatically,
/// because the request itself tells that service where you are. Shown next to the local VPN
/// address so you can see which way traffic leaves.
@Observable
final class PublicIP {
    static let shared = PublicIP()

    /// Services that answer with the address as plain text; the first that works is used.
    static let services = ["https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"]

    var address: String?
    var fetchedAt: Date?
    var isLoading = false
    var error: String?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task { @MainActor in
            var lastError = "No lookup service answered."
            for service in PublicIP.services {
                guard let url = URL(string: service) else { continue }
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
                request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        lastError = "HTTP \(http.statusCode) from \(url.host ?? service)"
                        continue
                    }
                    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard PublicIP.looksLikeAddress(text) else {
                        lastError = "Unexpected answer from \(url.host ?? service)"
                        continue
                    }
                    let changed = self.address != nil && self.address != text
                    self.address = text
                    self.fetchedAt = Date()
                    self.isLoading = false
                    if changed {
                        ActivityLog.shared.record(.action, "Public IP changed to \(text)", source: "What is my IP")
                    }
                    return
                } catch {
                    lastError = error.localizedDescription
                }
            }
            self.error = lastError
            self.isLoading = false
        }
    }

    static func looksLikeAddress(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 45 else { return false }
        let allowed = Set("0123456789abcdefABCDEF.:")
        return text.allSatisfy { allowed.contains($0) } && (text.contains(".") || text.contains(":"))
    }
}

/// Top-bar button: globe → fetch; shows the address, click to refresh, right-click to copy.
struct PublicIPButton: View {
    @Environment(SnippetStore.self) private var snippets

    var body: some View {
        let ip = PublicIP.shared
        Button {
            ip.refresh()
        } label: {
            HStack(spacing: 4) {
                if ip.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: ip.error == nil ? "globe" : "globe.badge.chevron.backward")
                }
                if let address = ip.address {
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ip.error == nil ? Color.secondary : Color.orange)
        .help(helpText)
        .contextMenu {
            if let address = ip.address {
                Button("Copy \(address)") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(address, forType: .string)
                }
            }
            Button("Refresh public IP") { ip.refresh() }
            Divider()
            Text("Local: \(snippets.lhost.isEmpty ? "— (One-liners › $LHOST)" : snippets.lhost)")
            ForEach(LocalAddress.interfaces()) { interface in
                Button("\(interface.name): \(interface.address)\(interface.isTunnel ? " (VPN)" : "") → $LHOST") {
                    snippets.lhost = interface.address
                    snippets.saveTarget()
                }
            }
        }
    }

    private var helpText: String {
        let ip = PublicIP.shared
        var lines: [String] = []
        if let address = ip.address, let at = ip.fetchedAt {
            lines.append("Public IP \(address) — checked \(at.formatted(date: .omitted, time: .shortened)); click to refresh")
        } else {
            lines.append("What is my IP? Click to ask \(PublicIP.services.first.flatMap { URL(string: $0)?.host } ?? "a lookup service") for your public address (only when you click)")
        }
        if let error = ip.error { lines.append("Last attempt failed: \(error)") }
        if !snippets.lhost.isEmpty { lines.append("Local / VPN address ($LHOST): \(snippets.lhost)") }
        return lines.joined(separator: "\n")
    }
}
