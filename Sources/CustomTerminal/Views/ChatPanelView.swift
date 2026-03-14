import SwiftUI
import SwiftData

struct ChatPanelView: View {
    let session: TerminalSession

    @Environment(ChatStore.self)  private var chatStore
    @Environment(AIStore.self)    private var aiStore

    @Query private var messages: [ChatMessage]

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    init(session: TerminalSession) {
        self.session = session
        let sid = session.id
        _messages = Query(
            filter: #Predicate<ChatMessage> { $0.sessionId == sid },
            sort: \.timestamp,
            animation: .default
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.currentDirectory == nil {
                cwdBanner
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(messages) { msg in
                            ChatMessageView(message: msg, session: session)
                                .id(msg.persistentModelID)
                        }
                        if chatStore.isSending {
                            if chatStore.streamingContent.isEmpty {
                                typingIndicator.id("typing")
                            } else {
                                streamingBubble.id("typing")
                            }
                        }
                        if let error = chatStore.sendError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                                .id("error")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                }
                .onChange(of: chatStore.isSending) { _, isSending in
                    if isSending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
                .onChange(of: chatStore.streamingContent) { _, _ in
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }

            Divider()

            inputBar
        }
        .background(Color.black.opacity(0.4))
    }

    // MARK: - Subviews

    private var cwdBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Directory tracking unavailable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.yellow)
                Text("Add to ~/.zshrc for richer AI context:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("function precmd { printf '\\e]7;file://%s%s\\a' \"$HOST\" \"$PWD\" }")
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.yellow.opacity(0.08))
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(chatStore.streamingContent)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .font(.system(size: 12))
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 10)
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 5, height: 5)
                    .foregroundStyle(.secondary)
                    .opacity(chatStore.isSending ? 1 : 0)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: chatStore.isSending
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this session…", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($inputFocused)
                .onSubmit { sendIfPossible() }
                .disabled(chatStore.isSending)

            Button {
                sendIfPossible()
            } label: {
                Image(systemName: chatStore.isSending ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(canSend ? .blue : .secondary)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatStore.isSending
    }

    private func sendIfPossible() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        Task {
            await chatStore.send(userText: text, session: session, apiKey: aiStore.apiKey, model: aiStore.model)
        }
    }
}
