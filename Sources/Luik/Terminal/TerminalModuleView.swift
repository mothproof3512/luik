import SwiftUI

// Note: this file deliberately does not import SwiftTerm, because SwiftTerm also defines a
// `Color` type that clashes with SwiftUI.Color. The NSViewRepresentable lives in TerminalSession.swift.

struct TerminalModuleView: View {
    @Environment(TerminalStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(store.sessions) { session in
                    TerminalTabChip(session: session,
                                    isSelected: session.id == store.selectedID,
                                    select: { store.select(session.id) },
                                    close: { store.close(session) })
                }
                Button {
                    store.newSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .help("New tab (⌘T)")
                Spacer()
                ConnectionsMenu()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.22))

            if let session = store.selected {
                TerminalViewRepresentable(session: session)
                    .id(session.id)
                    .onAppear {
                        store.focusSelected(afterDelay: true)
                    }
            } else {
                Spacer()
            }
        }
        // The view stays mounted while other tabs are shown (RootView keeps it in a ZStack), so
        // focus follows the tab switch here instead of onAppear/onDisappear.
        .onChange(of: ui.module) { _, module in
            if module == .terminal {
                store.focusSelected(afterDelay: true)
            } else {
                store.resignFocus()
            }
        }
    }
}

struct TerminalTabChip: View {
    let session: TerminalSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption)
            Text(session.title)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: 180)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .opacity(0.7)
            .help("Close tab (⌘W)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}
