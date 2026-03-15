import SwiftUI

struct SessionSidebarView: View {

    @Environment(SessionManager.self) private var sessionManager
    @State private var draggingId: UUID?

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
                        SessionRowView(session: session, isDragging: draggingId == session.id)
                            .onDrag {
                                draggingId = session.id
                                return NSItemProvider(object: session.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: SessionDropDelegate(
                                    targetId: session.id,
                                    draggingId: $draggingId,
                                    onMove: sessionManager.moveSession
                                )
                            )
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
    let isDragging: Bool
    @Environment(SessionManager.self) private var sessionManager

    var isActive: Bool { sessionManager.activeSessionId == session.id }

    var body: some View {
        Button(action: { sessionManager.activeSessionId = session.id }) {
            HStack(spacing: 6) {
                SessionStatusDot(session: session)

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
        .opacity(isDragging ? 0.4 : 1)
        .accessibilityLabel(session.name)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Status Dot

private struct SessionStatusDot: View {

    let session: TerminalSession

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch session.processStatus {
        case .idle:           return Color.primary.opacity(0.2)
        case .running:        return .green
        case .needsAttention: return .orange
        case .dead:           return Color.primary.opacity(0.1)
        }
    }

    private var accessibilityLabel: String {
        switch session.processStatus {
        case .idle:           return "idle"
        case .running:        return "running"
        case .needsAttention: return "needs attention"
        case .dead:           return "terminated"
        }
    }

    var body: some View {
        ZStack {
            // Outer ring for needsAttention
            if session.processStatus == .needsAttention {
                Circle()
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.35 : 1.0)
                .animation(
                    session.processStatus == .running && !reduceMotion
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
        }
        .frame(width: 10, height: 10)
        .onAppear { pulse = session.processStatus == .running }
        .onChange(of: session.processStatus) { _, newStatus in
            pulse = newStatus == .running
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHidden(false)
        .help(accessibilityLabel.capitalized)
    }
}

// MARK: - Drop Delegate

private struct SessionDropDelegate: DropDelegate {
    let targetId: UUID
    @Binding var draggingId: UUID?
    let onMove: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedId = draggingId, draggedId != targetId else { return false }
        onMove(draggedId, targetId)
        draggingId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingId != targetId
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
