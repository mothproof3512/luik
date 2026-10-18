import AppKit
import Foundation
import SwiftUI

/// One line of a tool's verdict (TLS, HTTP headers, DNS — same shape as the mail check).
typealias CheckItem = MailCheckItem

extension MailCheckItem.Level {
    var symbol: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .pass: return .green
        case .info: return .secondary
        case .warn: return .yellow
        case .fail: return .red
        }
    }

    var mark: String {
        switch self {
        case .pass: return "✅"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .fail: return "❌"
        }
    }
}

/// A verdict line as the tools draw it.
struct CheckItemRow: View {
    let item: CheckItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.level.symbol)
                .foregroundStyle(item.level.color)
                .frame(width: 16)
            Text(item.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.level.color.opacity(item.level == .pass ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The three buttons every check tool has once there is a result.
struct CheckResultButtons: View {
    let markdown: () -> String
    let findingTitle: String?
    let createFinding: () -> Void
    let addToTargets: (() -> Void)?
    @State private var copied = false
    @State private var created = false
    @State private var added = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(markdown(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy as Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        if let addToTargets {
            Button {
                addToTargets()
                added = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { added = false }
            } label: {
                Label(added ? "Added" : "Add to Targets", systemImage: added ? "checkmark" : "network")
            }
        }
        if let findingTitle {
            Button {
                createFinding()
                created = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { created = false }
            } label: {
                Label(created ? "Finding created" : "Create finding", systemImage: created ? "checkmark" : "exclamationmark.triangle")
            }
            .help("A finding “\(findingTitle)” with the issues in the description")
        }
    }
}

/// Runs a command-line tool with a time limit; returns stdout + stderr.
enum ShellTool {
    static func run(_ path: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval = 10) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        do { try process.run() } catch { return "" }
        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
        }
        try? inputPipe.fileHandleForWriting.close()
        var collected = Data()
        let reader = DispatchQueue(label: "luik.shelltool")
        let done = DispatchSemaphore(value: 0)
        reader.async {
            collected = output.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        _ = done.wait(timeout: .now() + 2)
        return String(decoding: collected, as: UTF8.self)
    }

    static func markdownList(_ items: [CheckItem]) -> String {
        items.map { "- \($0.level.mark) \($0.text)" }.joined(separator: "\n")
    }
}

/// The one toolbar every check tool has: input · ⚙︎ options (popover, only when there are any) ·
/// Run · spinner · the result buttons on the right.
struct CheckToolbar<Options: View, Trailing: View>: View {
    @Binding var text: String
    var placeholder: String
    var isRunning: Bool
    var hasOptions = false
    var optionsHelp = "Options"
    var run: () -> Void
    @ViewBuilder var options: () -> Options
    @ViewBuilder var trailing: () -> Trailing
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 380)
                .onSubmit(run)
            if hasOptions {
                Button {
                    showOptions.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help(optionsHelp)
                .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) { options() }
                        .padding(12)
                        .frame(minWidth: 260)
                }
            }
            Button(action: run) {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || text.trimmingCharacters(in: .whitespaces).isEmpty)
            if isRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
