import Foundation
import Observation

@Observable
final class SessionManager {

    var sessions: [TerminalSession] = []
    var activeSessionId: UUID?

    var aliasStore: AliasStore?
    /// Called with the closed session's ID after it has been removed.
    var onSessionClosed: ((UUID) -> Void)?
    let globalHistory = GlobalHistoryStore()

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionId }
    }

    private static let sessionsKey = "sessions.list"

    private struct PersistedSession: Codable {
        let id: UUID
        var name: String
    }

    init(aliasStore: AliasStore? = nil) {
        self.aliasStore = aliasStore
        restoreSessions()
        if sessions.isEmpty { addSession() }
    }

    func addSession() {
        let n = sessions.count + 1
        let s = makeSession(id: UUID(), name: "Session \(n)")
        sessions.append(s)
        activeSessionId = s.id
        persistSessions()
    }

    func closeSession(_ session: TerminalSession) {
        guard sessions.count > 1 else { return }   // Always keep at least one session
        let idx = sessions.firstIndex { $0.id == session.id }
        let closedId = session.id
        sessions.removeAll { $0.id == session.id }
        persistSessions()
        onSessionClosed?(closedId)

        if activeSessionId == session.id {
            if let idx {
                let newIdx = max(0, idx - 1)
                activeSessionId = sessions[safe: newIdx]?.id ?? sessions.first?.id
            } else {
                activeSessionId = sessions.first?.id
            }
        }
    }

    func closeActiveSession() {
        guard let active = activeSession else { return }
        closeSession(active)
    }

    func moveSession(draggedId: UUID, targetId: UUID) {
        guard draggedId != targetId,
              let from = sessions.firstIndex(where: { $0.id == draggedId }),
              let to   = sessions.firstIndex(where: { $0.id == targetId })
        else { return }
        sessions.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        persistSessions()
    }

    // MARK: - Persistence

    private func restoreSessions() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let persisted = try? JSONDecoder().decode([PersistedSession].self, from: data),
              !persisted.isEmpty
        else { return }

        sessions = persisted.map { makeSession(id: $0.id, name: $0.name) }
        activeSessionId = sessions.first?.id
    }

    private func persistSessions() {
        let persisted = sessions.map { PersistedSession(id: $0.id, name: $0.name) }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    private func makeSession(id: UUID, name: String) -> TerminalSession {
        let s = TerminalSession(id: id, name: name, aliasStore: aliasStore)
        s.globalHistory = globalHistory
        s.onNameChanged = { [weak self] in self?.persistSessions() }
        return s
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
