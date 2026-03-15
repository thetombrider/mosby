import Foundation
import Observation

// MARK: - PaletteResult

enum PaletteResult: Identifiable {
    case session(TerminalSession)
    case history(TerminalSession.HistoryEntry)
    case alias(AliasEntry)
    case action(TerminalAction)
    case match(SearchMatch)

    var id: String {
        switch self {
        case .session(let s):  "session-\(s.id)"
        case .history(let h):  "history-\(h.id)"
        case .alias(let a):    "alias-\(a.id)"
        case .action(let a):   "action-\(a.rawValue)"
        case .match(let m):    "match-\(m.id)"
        }
    }

    var title: String {
        switch self {
        case .session(let s):  s.name
        case .history(let h):  h.command
        case .alias(let a):    a.name
        case .action(let a):   a.displayName
        case .match(let m):    m.lineText
        }
    }

    var subtitle: String? {
        switch self {
        case .session:         nil
        case .history:         nil
        case .alias(let a):    a.command
        case .action:          nil
        case .match(let m):    m.session.name
        }
    }

    var icon: String {
        switch self {
        case .session:   "terminal"
        case .history:   "clock"
        case .alias:     "at"
        case .action:    "command"
        case .match:     "doc.text.magnifyingglass"
        }
    }

    var category: String {
        switch self {
        case .session:   "Sessions"
        case .history:   "History"
        case .alias:     "Aliases"
        case .action:    "Actions"
        case .match:     "Terminal Output"
        }
    }
}

// MARK: - CommandPaletteService

@Observable
@MainActor
final class CommandPaletteService {

    var query: String = ""
    var results: [PaletteResult] = []
    var selectedIndex: Int = 0
    var isSearching: Bool = false

    private var searchTask: Task<Void, Never>?

    // MARK: - Filter parsing

    /// Parses query prefix tokens into a filter mode and the effective search term.
    ///
    ///  `>`  → actions only
    ///  `@`  → sessions only
    ///  `!`  → history only
    ///  `#`  → aliases only
    ///  `/`  → terminal output search (slow)
    ///  none → all fast sources (no terminal buffer)
    enum Filter {
        case all, sessions, history, actions, aliases, matches

        static func parse(_ raw: String) -> (Filter, String) {
            guard let first = raw.first else { return (.all, raw) }
            let rest = String(raw.dropFirst()).trimmingCharacters(in: .whitespaces)
            switch first {
            case ">": return (.actions,  rest)
            case "@": return (.sessions, rest)
            case "!": return (.history,  rest)
            case "#": return (.aliases,  rest)
            case "/": return (.matches,  rest)
            default:  return (.all,      raw)
            }
        }
    }

    // MARK: - Search

    func search(
        sessions: [TerminalSession],
        history: [TerminalSession.HistoryEntry],
        aliases: [AliasEntry]
    ) {
        searchTask?.cancel()

        let raw = query.trimmingCharacters(in: .whitespaces)
        let (filter, term) = Filter.parse(raw)

        if raw.isEmpty {
            results = defaultResults(sessions: sessions, history: history)
            selectedIndex = 0
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            var found: [PaletteResult] = []

            // Sessions
            if filter == .all || filter == .sessions {
                let hits = sessions.filter {
                    term.isEmpty || $0.name.localizedCaseInsensitiveContains(term)
                }
                found += hits.map { .session($0) }
            }

            // App actions
            if filter == .all || filter == .actions {
                let hits = TerminalAction.allCases.filter {
                    term.isEmpty || $0.displayName.localizedCaseInsensitiveContains(term)
                }
                found += hits.map { .action($0) }
            }

            // Command history
            if filter == .all || filter == .history {
                let limit = filter == .all ? 20 : 200
                let hits = history
                    .filter { term.isEmpty || $0.command.localizedCaseInsensitiveContains(term) }
                    .prefix(limit)
                found += hits.map { .history($0) }
            }

            // Aliases
            if filter == .all || filter == .aliases {
                let hits = aliases.filter {
                    term.isEmpty ||
                    $0.name.localizedCaseInsensitiveContains(term) ||
                    $0.command.localizedCaseInsensitiveContains(term)
                }
                found += hits.map { .alias($0) }
            }

            // Terminal output — only with the `/` prefix or explicit .matches filter
            if filter == .matches, !term.isEmpty {
                var termHits: [PaletteResult] = []
                for session in sessions {
                    guard !Task.isCancelled else { break }
                    let lines = session.extractBufferLines()
                    var idx = 0
                    for (_, text) in lines {
                        var start = text.startIndex
                        while start < text.endIndex,
                              let range = text.range(
                                  of: term,
                                  options: [.caseInsensitive, .diacriticInsensitive],
                                  range: start..<text.endIndex
                              ) {
                            termHits.append(.match(
                                SearchMatch(
                                    session: session,
                                    matchIndexInSession: idx,
                                    lineText: text,
                                    matchRange: range
                                )
                            ))
                            idx += 1
                            start = range.upperBound
                        }
                    }
                }
                found += termHits
            }

            guard !Task.isCancelled else { return }
            let snapshot = found
            await MainActor.run {
                self.results = snapshot
                self.selectedIndex = snapshot.isEmpty ? 0 : min(self.selectedIndex, snapshot.count - 1)
                self.isSearching = false
            }
        }
    }

    // MARK: - Selection

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    var selectedResult: PaletteResult? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    // MARK: - Reset

    func clear() {
        searchTask?.cancel()
        query = ""
        results = []
        selectedIndex = 0
        isSearching = false
    }

    // MARK: - Defaults (empty query)

    private func defaultResults(
        sessions: [TerminalSession],
        history: [TerminalSession.HistoryEntry]
    ) -> [PaletteResult] {
        var r: [PaletteResult] = []
        r += sessions.map { .session($0) }
        r += history.prefix(5).map { .history($0) }
        r += TerminalAction.allCases.map { .action($0) }
        return r
    }
}
