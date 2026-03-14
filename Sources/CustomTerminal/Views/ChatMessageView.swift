import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    let session: TerminalSession

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            if isUser {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.7))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .font(.system(size: 12))
            } else {
                AssistantMessageView(content: message.content, session: session)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Segment model

private struct MessageSegment: Identifiable {
    let id = UUID()
    enum Kind {
        case text(String)
        case code(language: String?, body: String)
    }
    let kind: Kind
}

private func parseSegments(_ content: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    var remaining = content[...]
    let fence = "```"

    while !remaining.isEmpty {
        if let openRange = remaining.range(of: fence) {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(MessageSegment(kind: .text(trimmed)))
            }

            let afterOpen = remaining[openRange.upperBound...]
            let language: String?
            let bodyStart: String.Index
            if let nl = afterOpen.firstIndex(of: "\n") {
                let lang = String(afterOpen[afterOpen.startIndex..<nl]).trimmingCharacters(in: .whitespaces)
                language = lang.isEmpty ? nil : lang
                bodyStart = afterOpen.index(after: nl)
            } else {
                language = nil
                bodyStart = afterOpen.startIndex
            }

            let body = afterOpen[bodyStart...]
            if let closeRange = body.range(of: fence) {
                let code = String(body[body.startIndex..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    segments.append(MessageSegment(kind: .code(language: language, body: code)))
                }
                remaining = body[closeRange.upperBound...]
            } else {
                // No closing fence — treat the rest as plain text
                let rest = String(remaining[openRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty {
                    segments.append(MessageSegment(kind: .text(rest)))
                }
                break
            }
        } else {
            let rest = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                segments.append(MessageSegment(kind: .text(rest)))
            }
            break
        }
    }

    return segments
}

// MARK: - Assistant message

private struct AssistantMessageView: View {
    let content: String
    let session: TerminalSession

    private var segments: [MessageSegment] { parseSegments(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .text(let text):
                    Text(text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .font(.system(size: 12))
                case .code(let language, let body):
                    CodeBlockView(language: language, code: body, session: session)
                }
            }
        }
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "shell")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    session.injectText(code)
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)

            Divider()
                .overlay(Color.white.opacity(0.08))

            Text(code)
                .textSelection(.enabled)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
