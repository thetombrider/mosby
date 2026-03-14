import AppKit
import Observation

@Observable
final class KeybindingStore {

    var bindings: [TerminalAction: KeyCombo] = [:]

    private let defaultsKey = "Mosby.keybindings"

    init() {
        load()
        for action in TerminalAction.allCases where bindings[action] == nil {
            bindings[action] = action.defaultCombo
        }
    }

    func combo(for action: TerminalAction) -> KeyCombo {
        bindings[action] ?? action.defaultCombo
    }

    func set(combo: KeyCombo, for action: TerminalAction) {
        bindings[action] = combo
        save()
    }

    func reset(action: TerminalAction) {
        bindings[action] = action.defaultCombo
        save()
    }

    func resetAll() {
        for action in TerminalAction.allCases {
            bindings[action] = action.defaultCombo
        }
        save()
    }

    /// Returns the action matching the given key event, if any.
    func action(for event: NSEvent) -> TerminalAction? {
        TerminalAction.allCases.first { combo(for: $0).matches(event) }
    }

    // MARK: Persistence

    private func save() {
        let dict = bindings.reduce(into: [String: KeyCombo]()) { $0[$1.key.rawValue] = $1.value }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let dict = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
        else { return }
        bindings = dict.reduce(into: [:]) { result, pair in
            if let action = TerminalAction(rawValue: pair.key) { result[action] = pair.value }
        }
    }
}
