import Foundation
import SwiftData

@Model
final class ChatConversation {
    var sessionId: UUID
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(sessionId: UUID) {
        self.sessionId = sessionId
        self.createdAt = Date()
    }
}

@Model
final class ChatMessage {
    // Denormalized for reliable @Query filtering in views
    var sessionId: UUID
    var role: String        // "user" | "assistant"
    var content: String
    var timestamp: Date
    var conversation: ChatConversation?

    init(role: String, content: String, sessionId: UUID, conversation: ChatConversation? = nil) {
        self.role = role
        self.content = content
        self.sessionId = sessionId
        self.timestamp = Date()
        self.conversation = conversation
    }
}
