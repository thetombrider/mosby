import Foundation
import SwiftData
import Observation

@Observable
final class ChatStore {

    private let modelContext: ModelContext
    private let globalHistory: GlobalHistoryStore
    var isSending = false
    var sendError: String?
    var streamingContent = ""

    init(modelContext: ModelContext, globalHistory: GlobalHistoryStore) {
        self.modelContext = modelContext
        self.globalHistory = globalHistory
    }

    // MARK: - Conversation access

    func conversation(for sessionId: UUID) -> ChatConversation? {
        var descriptor = FetchDescriptor<ChatConversation>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func getOrCreateConversation(for sessionId: UUID) -> ChatConversation {
        if let existing = conversation(for: sessionId) { return existing }
        let conv = ChatConversation(sessionId: sessionId)
        modelContext.insert(conv)
        try? modelContext.save()
        return conv
    }

    func deleteConversation(for sessionId: UUID) {
        guard let conv = conversation(for: sessionId) else { return }
        modelContext.delete(conv)
        try? modelContext.save()
    }

    // MARK: - Send

    func send(userText: String, session: TerminalSession, apiKey: String, model: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let conv = getOrCreateConversation(for: session.id)

        let userMsg = ChatMessage(role: "user", content: trimmed, sessionId: session.id, conversation: conv)
        modelContext.insert(userMsg)
        try? modelContext.save()

        isSending = true
        sendError = nil
        streamingContent = ""

        // Extract all data from model instances before the async boundary
        let history = conv.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { AIService.ChatTurn(role: $0.role, content: $0.content) }

        let recentCommands = Array(globalHistory.entries.prefix(100).map(\.command))
        let terminalLines  = Array(session.extractBufferLines().suffix(100).map(\.text))
        let cwd            = session.currentDirectory ?? ""
        let dirContents: [String] = cwd.isEmpty
            ? []
            : (try? FileManager.default.contentsOfDirectory(atPath: cwd)) ?? []
        let recalled = await MemoryStore.shared.recall(query: trimmed)

        Task {
            await MemoryStore.shared.remember(trimmed, metadata: ["type": "chat", "role": "user"])
        }

        do {
            let stream = AIService.chatStream(
                messages: history,
                recentCommands: recentCommands,
                terminalLines: terminalLines,
                currentDirectory: cwd,
                directoryContents: dirContents,
                recalled: recalled,
                apiKey: apiKey,
                model: model
            )
            for try await token in stream {
                streamingContent += token
            }
            let assistantMsg = ChatMessage(role: "assistant", content: streamingContent, sessionId: session.id, conversation: conv)
            modelContext.insert(assistantMsg)
            try? modelContext.save()
            let assistantContent = streamingContent
            Task {
                await MemoryStore.shared.remember(assistantContent, metadata: ["type": "chat", "role": "assistant"])
            }
        } catch {
            sendError = error.localizedDescription
        }

        streamingContent = ""
        isSending = false
    }
}
