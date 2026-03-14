import Foundation
import Observation

@Observable
final class GlobalHistoryStore {

    var entries: [TerminalSession.HistoryEntry] = []

    private static let key      = "history.global"
    private static let maxCount = 1000

    init() {
        load()
    }

    func append(_ entry: TerminalSession.HistoryEntry) {
        entries.removeAll { $0.command == entry.command }
        entries.insert(entry, at: 0)
        save()
        Task {
            await MemoryStore.shared.remember(entry.command, metadata: ["type": "command"])
        }
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Private

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: Self.key),
              let loaded  = try? JSONDecoder().decode([TerminalSession.HistoryEntry].self, from: data)
        else { return }
        entries = loaded
    }

    private func save() {
        let toSave = Array(entries.prefix(Self.maxCount))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
