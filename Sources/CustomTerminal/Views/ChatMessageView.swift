import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    let session: TerminalSession

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isUser ? Color.blue.opacity(0.7) : Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .font(.system(size: 12))

                if !isUser, let code = extractFirstCodeBlock(message.content) {
                    Button {
                        session.injectText(code)
                    } label: {
                        Label("Insert", systemImage: "arrow.up.left.square")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    // Extracts the content of the first fenced code block (``` ... ```).
    private func extractFirstCodeBlock(_ content: String) -> String? {
        let fence = "```"
        guard let open = content.range(of: fence) else { return nil }
        let afterOpen = content[open.upperBound...]
        // Skip optional language tag on the same line
        let bodyStart: String.Index
        if let nl = afterOpen.firstIndex(of: "\n") {
            bodyStart = afterOpen.index(after: nl)
        } else {
            bodyStart = afterOpen.startIndex
        }
        let body = content[bodyStart...]
        guard let close = body.range(of: fence) else { return nil }
        let code = String(body[body.startIndex..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}
