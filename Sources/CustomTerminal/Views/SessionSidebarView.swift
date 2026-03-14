import SwiftUI

struct SessionSidebarView: View {

    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.3)

            // Session list
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(sessionManager.sessions, id: \.id) { session in
                        SessionRowView(session: session)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
            Divider().opacity(0.3)

            // New session button
            Button(action: { sessionManager.addSession() }) {
                Label("New Session", systemImage: "plus")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .onReceive(NotificationCenter.default.publisher(for: .closeSession)) { _ in
            sessionManager.closeActiveSession()
        }
    }
}

// MARK: - Session Row

private struct SessionRowView: View {

    let session: TerminalSession
    @Environment(SessionManager.self) private var sessionManager

    var isActive: Bool { sessionManager.activeSessionId == session.id }

    var body: some View {
        Button(action: { sessionManager.activeSessionId = session.id }) {
            HStack(spacing: 6) {
                // Status dot
                Circle()
                    .fill(session.isAlive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text(session.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Close button (only show for active session)
                if sessionManager.sessions.count > 1 {
                    Button(action: { sessionManager.closeSession(session) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(isActive ? 1 : 0)
                    .accessibilityLabel("Close \(session.name)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.name)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Hover highlight modifier

private struct HoverHighlightModifier: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(hovered ? Color.white.opacity(0.05) : Color.clear)
            .onHover { hovered = $0 }
    }
}

private extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlightModifier())
    }
}
