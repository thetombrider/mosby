import SwiftUI
import SwiftTerm

struct GlobalSearchView: View {
    @Binding var isPresented: Bool
    @Environment(SessionManager.self) private var sessionManager

    @State private var searchService = GlobalSearchService()
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
                .background(Color.white.opacity(0.1))
            resultsList
        }
        .frame(width: 500)
        .frame(maxHeight: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear { isQueryFocused = true }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onChange(of: searchService.query) {
            searchService.search(in: sessionManager.sessions)
        }
        .onChange(of: searchService.caseSensitive) {
            searchService.search(in: sessionManager.sessions)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search terminal output…", text: $searchService.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isQueryFocused)

            if searchService.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchService.query.isEmpty {
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $searchService.caseSensitive) {
                Text("Aa")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(searchService.caseSensitive ? .primary : .secondary)
            .help("Case Sensitive")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        if searchService.query.isEmpty {
            emptyPrompt(icon: "magnifyingglass", message: "Type to search across all open sessions")
        } else if !searchService.isSearching && searchService.matches.isEmpty {
            emptyPrompt(icon: "xmark.circle", message: "No matches found")
        } else {
            let groups = searchService.matchesBySession(sessionOrder: sessionManager.sessions)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.session.id) { group in
                        sessionSection(session: group.session, matches: group.matches)
                    }
                }
            }
        }
    }

    private func sessionSection(session: TerminalSession, matches: [SearchMatch]) -> some View {
        Section {
            ForEach(matches) { match in
                MatchRow(match: match, query: searchService.query, caseSensitive: searchService.caseSensitive)
                    .onTapGesture {
                        jump(to: match)
                    }
            }
        } header: {
            HStack {
                Text(session.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("(\(matches.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
    }

    private func emptyPrompt(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Helpers

    private var summaryText: String {
        let count = searchService.matches.count
        if count == 0 { return "No matches" }
        let sessionCount = Set(searchService.matches.map { ObjectIdentifier($0.session) }).count
        let s = count == 1 ? "match" : "matches"
        return "\(count) \(s) in \(sessionCount) session\(sessionCount == 1 ? "" : "s")"
    }

    private func jump(to match: SearchMatch) {
        dismiss()
        // Switch to the session containing the match.
        sessionManager.activeSessionId = match.session.id
        // Use SwiftTerm's public findNext to locate, select, and scroll to the match.
        // Clear any prior search state, then advance to the Nth match.
        let tv = match.session.terminalView
        let options = SearchOptions(caseSensitive: searchService.caseSensitive)
        tv.clearSearch()
        for _ in 0...match.matchIndexInSession {
            tv.findNext(searchService.query, options: options, scrollToResult: true)
        }
    }

    private func dismiss() {
        searchService.clear()
        isPresented = false
    }
}

// MARK: - MatchRow

private struct MatchRow: View {
    let match: SearchMatch
    let query: String
    let caseSensitive: Bool

    @State private var isHovered = false

    var body: some View {
        Text(highlightedText)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovered ? Color.white.opacity(0.07) : Color.clear)
            .onHover { isHovered = $0 }
    }

    private var highlightedText: AttributedString {
        var attributed = AttributedString(match.lineText)

        let compareOptions: String.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]

        var searchStart = match.lineText.startIndex
        while searchStart < match.lineText.endIndex,
              let range = match.lineText.range(of: query, options: compareOptions, range: searchStart..<match.lineText.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .init(.init(white: 1, alpha: 0.25))
                attributed[attrRange].foregroundColor = .white
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}
