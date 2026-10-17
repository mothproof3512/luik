import AppKit
import Foundation
import Network
import Observation
import SwiftUI

/// A host (and optionally a port) to probe every few minutes: "am I still allowed in?"
struct CanaryTarget: Identifiable, Codable, Hashable {
    var id = UUID()
    var address: String
    /// nil = ICMP ping; otherwise a TCP connect to this port.
    var port: Int?
    var label: String = ""

    init(id: UUID = UUID(), address: String, port: Int? = nil, label: String = "") {
        self.id = id
        self.address = address
        self.port = port
        self.label = label
    }

    private enum CodingKeys: String, CodingKey { case id, address, port, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    var display: String {
        port.map { "\(address):\($0)" } ?? "\(address) (ping)"
    }
}

/// What the engagement's canary.json holds.
struct CanaryConfig: Codable {
    var enabled = false
    var intervalMinutes = 5
    var targets: [CanaryTarget] = []

    private enum CodingKeys: String, CodingKey { case enabled, intervalMinutes, targets }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 5
        targets = try c.decodeIfPresent([CanaryTarget].self, forKey: .targets) ?? []
    }
}

/// Live state of one target (not saved).
struct CanaryState: Hashable {
    enum Status: Hashable {
        case unknown, up, down

        var label: String {
            switch self {
            case .unknown: return "Not checked yet"
            case .up: return "Reachable"
            case .down: return "Unreachable"
            }
        }
    }

    var status: Status = .unknown
    var latencyMs: Double?
    var lastChecked: Date?
    var lastChange: Date?
    var detail: String = ""
    /// Most recent results, newest last (for the little history strip).
    var history: [Bool] = []
}

/// Reachability canary: probes a few in-scope hosts every N minutes while enabled, so a block
/// by the client's defences shows up as a red badge — and the moment of the block lands in the
/// Log for the report. Off by default and per engagement, because every probe is traffic to the
/// client's systems.
@Observable
final class CanaryStore {
    static let shared = CanaryStore()

    private static let fileName = "canary.json"
    static let intervals = [1, 2, 5, 10, 15, 30, 60]
    static let timeoutSeconds: Double = 4

    var config = CanaryConfig()
    var states: [UUID: CanaryState] = [:]
    var isChecking = false
    var lastRun: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var saver = Debouncer()
    @ObservationIgnored private let queue = DispatchQueue(label: "luik.canary", qos: .utility)

    init() {
        load()
    }

    // MARK: - Per engagement

    func reload() {
        saver.flush()
        stopTimer()
        states = [:]
        load()
    }

    private func load() {
        config = Storage.load(CanaryConfig.self, at: EngagementStore.shared.fileURL(CanaryStore.fileName)) ?? CanaryConfig()
        if config.enabled { startTimer() }
    }

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(CanaryStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.config, at: url)
        }
    }

    func flush() {
        saver.flush()
    }

    // MARK: - Summary

    enum Overall { case off, unknown, up, down }

    var overall: Overall {
        guard config.enabled, !config.targets.isEmpty else { return .off }
        let statuses = config.targets.map { states[$0.id]?.status ?? .unknown }
        if statuses.contains(.down) { return .down }
        if statuses.allSatisfy({ $0 == .up }) { return .up }
        return .unknown
    }

    var downCount: Int {
        config.targets.filter { states[$0.id]?.status == .down }.count
    }

    func state(for target: CanaryTarget) -> CanaryState {
        states[target.id] ?? CanaryState()
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        scheduleSave()
        if enabled {
            ActivityLog.shared.record(.action, "Reachability canary started: \(config.targets.map { $0.display }.joined(separator: ", ")) every \(config.intervalMinutes) min", source: "Canary")
            startTimer()
            checkNow()
        } else {
            stopTimer()
            ActivityLog.shared.record(.action, "Reachability canary stopped", source: "Canary")
        }
    }

    func setInterval(_ minutes: Int) {
        config.intervalMinutes = minutes
        scheduleSave()
        if config.enabled { startTimer() }
    }

    func add(_ target: CanaryTarget) {
        guard !config.targets.contains(where: { $0.address == target.address && $0.port == target.port }) else { return }
        config.targets.append(target)
        scheduleSave()
        if config.enabled { check(target) }
    }

    func remove(_ id: UUID) {
        config.targets.removeAll { $0.id == id }
        states[id] = nil
        scheduleSave()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let interval = TimeInterval(max(config.intervalMinutes, 1) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
        timer?.tolerance = 5
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Probing

    func checkNow() {
        guard !config.targets.isEmpty else { return }
        isChecking = true
        lastRun = Date()
        let group = DispatchGroup()
        for target in config.targets {
            group.enter()
            check(target) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isChecking = false
        }
    }

    func check(_ target: CanaryTarget, completion: (() -> Void)? = nil) {
        let started = Date()
        let finish: (Bool, String) -> Void = { [weak self] up, detail in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                let latency = Date().timeIntervalSince(started) * 1000
                var state = self.states[target.id] ?? CanaryState()
                let previous = state.status
                state.status = up ? .up : .down
                state.latencyMs = up ? latency : nil
                state.lastChecked = Date()
                state.detail = detail
                state.history.append(up)
                if state.history.count > 30 { state.history.removeFirst(state.history.count - 30) }
                if previous != state.status {
                    state.lastChange = Date()
                    if previous != .unknown || !up {
                        ActivityLog.shared.record(.action,
                                                  up ? "Canary \(target.display) reachable again" : "Canary \(target.display) UNREACHABLE — \(detail)",
                                                  source: "Canary")
                    }
                }
                self.states[target.id] = state
                completion?()
            }
        }
        if let port = target.port {
            tcpProbe(host: target.address, port: port, completion: finish)
        } else {
            queue.async {
                let (up, detail) = CanaryStore.pingProbe(host: target.address)
                finish(up, detail)
            }
        }
    }

    private func tcpProbe(host: String, port: Int, completion: @escaping (Bool, String) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            completion(false, "invalid port")
            return
        }
        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        var done = false
        let lock = NSLock()
        func settle(_ up: Bool, _ detail: String) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            connection.cancel()
            completion(up, detail)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: settle(true, "TCP connect to port \(port) succeeded")
            case .failed(let error): settle(false, "TCP connect failed: \(error.localizedDescription)")
            case .waiting(let error): settle(false, "No route / waiting: \(error.localizedDescription)")
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + CanaryStore.timeoutSeconds) {
            settle(false, "TCP connect timed out after \(Int(CanaryStore.timeoutSeconds)) s")
        }
    }

    /// One ICMP echo through the system's ping (no raw sockets needed).
    static func pingProbe(host: String) -> (Bool, String) {
        let tool = "/sbin/ping"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return (false, "ping not available") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-c", "1", "-W", "\(Int(timeoutSeconds * 1000))", "-t", "\(Int(timeoutSeconds) + 1)", "-n", "-q", host]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return (false, "could not run ping: \(error.localizedDescription)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        if process.terminationStatus == 0 {
            if let range = text.range(of: #"= ([0-9.]+)/"#, options: .regularExpression) {
                return (true, "ICMP echo reply, rtt \(text[range].dropFirst(2).dropLast()) ms")
            }
            return (true, "ICMP echo reply")
        }
        let last = text.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return (false, "no ICMP reply" + (last.isEmpty ? "" : " (\(last))"))
    }
}

/// Top-bar badge while the canary runs: green all up, red when something is unreachable.
struct CanaryIndicator: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        let canary = CanaryStore.shared
        if canary.overall != .off {
            Button {
                ui.open(.reachability)
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color(canary.overall))
                        .frame(width: 8, height: 8)
                    Text(canary.overall == .down ? "\(canary.downCount) unreachable" : "canary")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(canary.overall == .down ? Color.red : Color.secondary)
            .help(helpText(canary))
        }
    }

    private func color(_ overall: CanaryStore.Overall) -> Color {
        switch overall {
        case .off, .unknown: return .gray
        case .up: return .green
        case .down: return .red
        }
    }

    private func helpText(_ canary: CanaryStore) -> String {
        var lines = ["Reachability canary — every \(canary.config.intervalMinutes) min; click to open"]
        for target in canary.config.targets {
            let state = canary.state(for: target)
            lines.append("\(target.display): \(state.status.label)\(state.latencyMs.map { String(format: " · %.0f ms", $0) } ?? "")")
        }
        return lines.joined(separator: "\n")
    }
}
