import SwiftUI

/// The one empty state: an icon, a title, one sentence, and (optionally) one or two actions.
struct EmptyState<Actions: View>: View {
    var icon: String
    var title: String
    var message: String
    @ViewBuilder var actions: () -> Actions

    init(icon: String, title: String, message: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { actions() }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension EmptyState where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
