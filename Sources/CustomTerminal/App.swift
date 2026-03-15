import SwiftUI
import AppKit
import SwiftData

struct MosbyApp: App {
    @State private var aliasStore      = AliasStore()
    @State private var keybindingStore = KeybindingStore()
    @State private var sessionManager: SessionManager
    @State private var aiStore         = AIStore()
    @State private var paneNav         = PaneNavigationStore()
    @State private var chatStore: ChatStore

    private let container: ModelContainer

    init() {
        let schema = Schema([ChatConversation.self, ChatMessage.self])
        let c = (try? ModelContainer(for: schema)) ?? {
            let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: cfg)
        }()
        container = c

        let aliases = AliasStore()
        let sm = SessionManager(aliasStore: aliases)
        _aliasStore      = State(initialValue: aliases)
        _keybindingStore = State(initialValue: KeybindingStore())
        _sessionManager  = State(initialValue: sm)
        _aiStore         = State(initialValue: AIStore())
        _chatStore       = State(initialValue: ChatStore(modelContext: c.mainContext, globalHistory: sm.globalHistory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(aliasStore)
                .environment(keybindingStore)
                .environment(aiStore)
                .environment(paneNav)
                .environment(chatStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                    sessionManager.onSessionClosed = { id in
                        chatStore.deleteConversation(for: id)
                    }
                    installKeyboardForwarder()
                    Task { await MemoryStore.shared.open() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await MemoryStore.shared.close() }
                }
        }
        .modelContainer(container)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mosby") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "Developer: Tommaso Minuto",
                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                        )
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                // ⌘W stays hardcoded — standard macOS convention
                Button("Close Tab") { NotificationCenter.default.post(name: .closeSession, object: nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Terminal") {
                Button("Manage Aliases…") {
                    NotificationCenter.default.post(name: .openAliases, object: nil)
                }
                Button("Manage Keybindings…") {
                    NotificationCenter.default.post(name: .openKeybindings, object: nil)
                }
                Divider()
                Button("Toggle Chat") {
                    NotificationCenter.default.post(name: .toggleChat, object: nil)
                }
                Divider()
                Button("AI Settings…") {
                    NotificationCenter.default.post(name: .openAISettings, object: nil)
                }
                Divider()
                Button("Clear History") {
                    NotificationCenter.default.post(name: .clearHistory, object: nil)
                }
            }
        }
    }

    /// Intercept keyDown before SwiftUI/AppKit consume them.
    /// All configurable actions route through dispatch(action:). Only truly
    /// conditional or non-action key handling remains inline.
    private func installKeyboardForwarder() {
        // ── Auto-trigger: history-first completion, AI fallback ───────────────
        var debounceTask: Task<Void, Never>?
        NotificationCenter.default.addObserver(forName: .terminalInputChanged, object: nil, queue: .main) { _ in
            guard aiStore.isEnabled else { return }
            // Every keystroke cancels in-flight request and ghost text
            if aiStore.isLoadingCompletion || aiStore.pendingSuggestion != nil {
                aiStore.clearCompletion()
                sessionManager.activeSession?.terminalView.hideGhostText()
            }
            debounceTask?.cancel()

            guard let session = sessionManager.activeSession,
                  !session.currentInputBuffer.isEmpty else { return }

            // History lookup is instant — show suggestion immediately if found
            if let match = self.findHistorySuggestion(for: session.currentInputBuffer, in: session) {
                aiStore.pendingSuggestion = match
                let suffix = String(match.dropFirst(session.currentInputBuffer.count))
                session.terminalView.showGhostText(suffix)
                return  // skip AI debounce
            }

            // No history match → fall back to AI after debounce
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                guard let session = sessionManager.activeSession,
                      !session.currentInputBuffer.isEmpty else { return }
                triggerAICompletion()
            }
        }
        // ─────────────────────────────────────────────────────────────────────

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow else { return event }

            // Don't intercept when a sheet is active (covers alias/keybinding manager)
            guard window.sheetParent == nil, window.sheets.isEmpty else { return event }

            // ── Pane navigation mode ────────────────────────────────────────
            if event.keyCode == 53 { // ESC
                let fr = window.firstResponder
                let inTextField = fr is NSTextField || fr is NSText

                if paneNav.isNavigating {
                    // Second ESC → exit nav mode, refocus terminal
                    paneNav.exitNavigation()
                    paneNav.activePane = .terminal
                    sessionManager.activeSession?.terminalView.window?
                        .makeFirstResponder(sessionManager.activeSession?.terminalView)
                } else if paneNav.activePane != .terminal {
                    // ESC from a sidebar → enter nav mode highlighting that pane
                    paneNav.enterNavigation(currentPane: paneNav.activePane)
                    paneNav.activePane = .terminal
                } else if inTextField {
                    // ESC from a text field → refocus terminal
                    sessionManager.activeSession?.terminalView.window?
                        .makeFirstResponder(sessionManager.activeSession?.terminalView)
                } else {
                    // ESC from terminal → enter nav mode
                    paneNav.enterNavigation(currentPane: .terminal)
                }
                return nil
            }

            if paneNav.isNavigating {
                switch event.keyCode {
                case 123: paneNav.move(.left);  return nil  // ←
                case 124: paneNav.move(.right); return nil  // →
                case 125: paneNav.move(.down);  return nil  // ↓
                case 126: paneNav.move(.up);    return nil  // ↑
                case 36:  // Enter → dive into the focused pane
                    let target = paneNav.focusedPane
                    paneNav.exitNavigation()
                    self.focusPane(target)
                    return nil
                default:
                    // Any other key exits nav mode and falls through
                    paneNav.exitNavigation()
                }
            }
            // ────────────────────────────────────────────────────────────────

            // All configurable keybindings — single dispatch point
            if let action = keybindingStore.action(for: event) {
                self.dispatch(action: action)
                return nil
            }

            // ── Shift variant of line-nav (⌘⇧← / ⌘⇧→ behave same as ⌘← / ⌘→) ──
            if let session = sessionManager.activeSession {
                let mods = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting([.numericPad, .function])
                if mods == NSEvent.ModifierFlags([.command, .shift]) {
                    if event.keyCode == keybindingStore.combo(for: .selectToLineStart).keyCode {
                        session.terminalView.selectToLineStart(); return nil
                    }
                    if event.keyCode == keybindingStore.combo(for: .selectToLineEnd).keyCode {
                        session.terminalView.selectToLineEnd(); return nil
                    }
                }
            }
            // ─────────────────────────────────────────────────────────────────

            // ── Conditional delete of selected input text ─────────────────────
            if let session = sessionManager.activeSession {
                switch event.keyCode {
                case 51, 117:  // Delete / Forward Delete
                    if session.terminalView.inputSelectionLength > 0 {
                        session.terminalView.deleteSelection(); return nil
                    }
                default: break
                }
            }
            // ─────────────────────────────────────────────────────────────────

            // Let ⌘ combos reach the macOS menu system
            guard !event.modifierFlags.contains(.command) else { return event }

            // Don't steal input from SwiftUI text fields
            let fr = window.firstResponder
            if fr is NSTextField || fr is NSText { return event }

            // Let SwiftUI handle events when a sidebar or chat pane is active
            if paneNav.activePane != .terminal { return event }

            // ── Right Arrow: accept inline ghost suggestion ───────────────────
            if event.keyCode == 124,  // Right Arrow
               let suggestion = aiStore.pendingSuggestion,
               let session = sessionManager.activeSession {
                let typed = session.currentInputBuffer
                let suffix = suggestion.hasPrefix(typed)
                    ? String(suggestion.dropFirst(typed.count))
                    : suggestion
                if !suffix.isEmpty {
                    session.terminalView.send(txt: suffix)
                }
                aiStore.clearCompletion()
                session.terminalView.hideGhostText()
                debounceTask?.cancel()
                return nil
            }
            // ─────────────────────────────────────────────────────────────────

            // Any key while an AI suggestion is visible → dismiss it, then forward
            if aiStore.pendingSuggestion != nil || aiStore.isLoadingCompletion {
                aiStore.clearCompletion()
                sessionManager.activeSession?.terminalView.hideGhostText()
            }

            guard let session = sessionManager.activeSession else { return event }
            session.terminalView.keyDown(with: event)
            return nil
        }
    }

    /// Single dispatch point for all configurable terminal actions.
    private func dispatch(action: TerminalAction) {
        switch action {
        case .selectToLineStart:
            sessionManager.activeSession?.terminalView.selectToLineStart()

        case .selectToLineEnd:
            sessionManager.activeSession?.terminalView.selectToLineEnd()

        case .aiComplete:
            guard aiStore.isEnabled else { return }
            if let suggestion = aiStore.pendingSuggestion {
                sessionManager.activeSession?.injectText(suggestion)
                aiStore.clearCompletion()
            } else if !aiStore.isLoadingCompletion {
                triggerAICompletion()
            }

        default:
            if let name = action.notificationName {
                NotificationCenter.default.post(name: name, object: nil)
            }
        }
    }

    /// Focus into the given pane after exiting navigation mode.
    private func focusPane(_ pane: PaneNavigationStore.Pane) {
        paneNav.activePane = pane
        switch pane {
        case .terminal:
            sessionManager.activeSession?.terminalView.window?
                .makeFirstResponder(sessionManager.activeSession?.terminalView)
        case .chat:
            NotificationCenter.default.post(name: .focusChatInput, object: nil)
        case .sessions:
            NotificationCenter.default.post(name: .focusSessions, object: nil)
        case .history:
            NotificationCenter.default.post(name: .focusHistory, object: nil)
        }
    }

    /// Returns the most recent history entry that extends `partial`, or nil if none.
    private func findHistorySuggestion(for partial: String, in session: TerminalSession) -> String? {
        session.commandHistory.first {
            $0.command.hasPrefix(partial) && $0.command != partial
        }?.command
    }

    private func triggerAICompletion() {
        aiStore.completionTask?.cancel()

        guard let session = sessionManager.activeSession else { return }
        let partial = session.currentInputBuffer
        let history = session.commandHistory.prefix(20).map(\.command)

        aiStore.isLoadingCompletion = true
        aiStore.pendingSuggestion   = nil
        aiStore.completionError     = nil
        session.terminalView.hideGhostText()

        aiStore.completionTask = Task { @MainActor in
            do {
                // Fetch completion system prompt from Langfuse (with fallback)
                let langfusePrompt = await LangfuseClient.shared.fetchPrompt(name: "mosby-completion")
                let systemPrompt   = langfusePrompt?.text ?? AIService.defaultCompletionSystemPrompt

                let suggestion = try await AIService.completeCommand(
                    partial: partial,
                    history: Array(history),
                    apiKey: aiStore.apiKey,
                    model: aiStore.model,
                    systemPromptOverride: systemPrompt
                )

                aiStore.isLoadingCompletion = false

                // Only show if suggestion extends what the user currently has typed
                let typed = session.currentInputBuffer
                guard !typed.isEmpty, suggestion.hasPrefix(typed) else {
                    aiStore.clearCompletion()
                    return
                }

                aiStore.pendingSuggestion = suggestion
                let suffix = String(suggestion.dropFirst(typed.count))
                session.terminalView.showGhostText(suffix)
            } catch {
                aiStore.completionError     = error.localizedDescription
                aiStore.isLoadingCompletion = false
                // Auto-dismiss error after 3 s
                try? await Task.sleep(for: .seconds(3))
                if aiStore.pendingSuggestion == nil { aiStore.completionError = nil }
            }
        }
    }
}

extension Notification.Name {
    static let newSession           = Notification.Name("Mosby.newSession")
    static let closeSession         = Notification.Name("Mosby.closeSession")
    static let openAliases          = Notification.Name("Mosby.openAliases")
    static let toggleSessions       = Notification.Name("Mosby.toggleSessions")
    static let toggleHistory        = Notification.Name("Mosby.toggleHistory")
    static let toggleChat           = Notification.Name("Mosby.toggleChat")
    static let openKeybindings      = Notification.Name("Mosby.openKeybindings")
    static let openAISettings       = Notification.Name("Mosby.openAISettings")
    static let toggleSearch         = Notification.Name("Mosby.toggleSearch")
    static let toggleCommandPalette = Notification.Name("Mosby.toggleCommandPalette")
    static let terminalInputChanged = Notification.Name("Mosby.terminalInputChanged")
    static let clearHistory         = Notification.Name("Mosby.clearHistory")
    static let focusChatInput       = Notification.Name("Mosby.focusChatInput")
    static let focusSessions        = Notification.Name("Mosby.focusSessions")
    static let focusHistory         = Notification.Name("Mosby.focusHistory")
}
