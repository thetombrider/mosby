import Foundation
import Observation

struct AliasEntry: Identifiable, Codable {
    var id: UUID
    var name: String      // the short alias, e.g. "ll"
    var command: String   // the expansion,  e.g. "ls -la"

    init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

@Observable
final class AliasStore {

    var aliases: [AliasEntry] = [] {
        didSet { save() }
    }

    private let defaultsKey = "Mosby.aliases"

    init() { load() }

    /// Returns the expanded command if `input` starts with a known alias name.
    /// Replaces only the alias token, preserving any trailing arguments.
    /// e.g. alias "d" → "rm": "d file.csv" expands to "rm file.csv"
    func expand(_ input: String) -> String? {
        // Sort by longest name first so "ll" doesn't shadow "l" etc.
        for entry in aliases.sorted(by: { $0.name.count > $1.name.count }) {
            if input == entry.name {
                return entry.command
            }
            if input.hasPrefix(entry.name + " ") {
                let args = input.dropFirst(entry.name.count) // keeps the leading space
                return entry.command + args
            }
        }
        return nil
    }

    func add(name: String, command: String) {
        // Replace existing alias with the same name if present
        if let idx = aliases.firstIndex(where: { $0.name == name }) {
            aliases[idx].command = command
        } else {
            aliases.append(AliasEntry(name: name, command: command))
        }
    }

    func delete(at offsets: IndexSet) {
        aliases.remove(atOffsets: offsets)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(aliases) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([AliasEntry].self, from: data)
        else { return }
        aliases = decoded
    }
}
