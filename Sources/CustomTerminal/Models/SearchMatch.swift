import Foundation

struct SearchMatch: Identifiable {
    let id = UUID()
    let session: TerminalSession
    /// 0-based index among all matches in this session — used to navigate via findNext.
    let matchIndexInSession: Int
    /// Full trimmed line text, for display in the results list.
    let lineText: String
    /// Range within lineText where the query matched, for highlight rendering.
    let matchRange: Range<String.Index>
}
