import SwiftUI

struct HistorySidebarView: View {

    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        if let session = sessionManager.activeSession {
            HistoryContent(session: session)
        } else {
            VStack {
                Spacer()
                Text("No active session")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.6))
                Spacer()
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
    }
}

private struct HistoryContent: View {

    let session: TerminalSession
    @Environment(SessionManager.self) private var sessionManager
    @State private var searchText = ""

    private var history: [TerminalSession.HistoryEntry] {
        let all = sessionManager.globalHistory.entries
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.command.localizedStandardContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("HISTORY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !sessionManager.globalHistory.entries.isEmpty {
                    Button("Clear") {
                        sessionManager.globalHistory.clear()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.3)

            // History list
            if history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(searchText.isEmpty ? "No commands yet" : "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Spacer()
                }
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(history) { entry in
                            HistoryEntryRow(entry: entry) {
                                session.inject(command: entry.command)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}

// MARK: - History Entry Row

private struct HistoryEntryRow: View {

    let entry: TerminalSession.HistoryEntry
    let onRun: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
            Text(entry.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovered ? Color.white.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.command)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onRun)
        .onHover { hovered = $0 }
        .onTapGesture(perform: onRun)
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}
