import Foundation
import Observation

@Observable
final class AIStore {

    // MARK: - Persistent settings

    var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != apiKey { apiKey = trimmed; return }
            UserDefaults.standard.set(trimmed, forKey: Keys.apiKey)
        }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    // MARK: - Completion overlay state (not persisted)

    var pendingSuggestion: String? = nil
    var isLoadingCompletion: Bool = false
    var completionError: String? = nil

    /// In-flight completion task — stored here (reference type) so App.swift (a struct) can cancel it.
    var completionTask: Task<Void, Never>?

    // MARK: - Available models

    static let availableModels: [(id: String, name: String)] = [
        ("google/gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"),
        ("inception/mercury-2", "Mercury 2"),
        ("arcee-ai/trinity-large-preview:free", "Trinity Large Preview"),
        ("minimax/minimax-m2.5:free", "MiniMax M2.5"),
        ("qwen/qwen3.5-9b", "Qwen 3.5 9B"),
    ]

    // MARK: - Init

    init() {
        self.apiKey    = (UserDefaults.standard.string(forKey: Keys.apiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.model     = UserDefaults.standard.string(forKey: Keys.model) ?? "google/gemini-2.5-flash-lite"
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    // MARK: - Helpers

    func clearCompletion() {
        completionTask?.cancel()
        completionTask      = nil
        pendingSuggestion   = nil
        isLoadingCompletion = false
        completionError     = nil
    }

    // MARK: - Private

    private enum Keys {
        static let apiKey  = "Mosby.ai.apiKey"
        static let model   = "Mosby.ai.model"
        static let enabled = "Mosby.ai.enabled"
    }
}
