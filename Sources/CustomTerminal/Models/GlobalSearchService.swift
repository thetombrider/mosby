import Foundation
import Observation

@Observable
final class GlobalSearchService {
    var query: String = ""
    var matches: [SearchMatch] = []
    var isSearching: Bool = false
    var caseSensitive: Bool = false

    private var searchTask: Task<Void, Never>?

    func search(in sessions: [TerminalSession]) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            matches = []
            return
        }

        let capturedQuery = trimmed
        let capturedCaseSensitive = caseSensitive

        searchTask = Task {
            await MainActor.run { isSearching = true }

            var found: [SearchMatch] = []

            for session in sessions {
                let lines = session.extractBufferLines()
                var sessionMatchIndex = 0
                let compareOptions: String.CompareOptions = capturedCaseSensitive
                    ? []
                    : [.caseInsensitive, .diacriticInsensitive]

                for (_, text) in lines {
                    var searchStart = text.startIndex
                    while searchStart < text.endIndex {
                        guard let range = text.range(
                            of: capturedQuery,
                            options: compareOptions,
                            range: searchStart..<text.endIndex
                        ) else { break }

                        found.append(SearchMatch(
                            session: session,
                            matchIndexInSession: sessionMatchIndex,
                            lineText: text,
                            matchRange: range
                        ))
                        sessionMatchIndex += 1
                        searchStart = range.upperBound
                    }
                }
            }

            guard !Task.isCancelled else { return }
            let results = found
            await MainActor.run {
                self.matches = results
                self.isSearching = false
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        matches = []
        isSearching = false
    }

    /// Groups matches by session, preserving session order.
    func matchesBySession(sessionOrder: [TerminalSession]) -> [(session: TerminalSession, matches: [SearchMatch])] {
        let grouped = Dictionary(grouping: matches, by: { ObjectIdentifier($0.session) })
        return sessionOrder.compactMap { session in
            guard let sessionMatches = grouped[ObjectIdentifier(session)], !sessionMatches.isEmpty else {
                return nil
            }
            return (session, sessionMatches)
        }
    }
}
