import SwiftUI


struct ContentView: View {
    @Environment(SessionManager.self)  private var sessionManager
    @Environment(AliasStore.self)      private var aliasStore
    @Environment(KeybindingStore.self) private var keybindingStore
    @Environment(AIStore.self)         private var aiStore
    @Environment(PaneNavigationStore.self) private var paneNav
    @Environment(ChatStore.self)       private var chatStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSessions       = true
    @State private var showHistory        = true
    @State private var showChat           = true
    @State private var showingSearch      = false

    @State private var showingAliases     = false
    @State private var showingKeybindings = false
    @State private var showingAISettings  = false

    private var showCompletionBanner: Bool {
        aiStore.isEnabled && aiStore.completionError != nil
    }

    var body: some View {
        HSplitView {
            if showSessions {
                SessionSidebarView()
                    .frame(minWidth: 140, idealWidth: 200, maxWidth: 320)
                    .paneHighlight(.sessions, store: paneNav)
            }

            VSplitView {
                ZStack(alignment: .bottom) {
                    TerminalContainerView(sessionManager: sessionManager)

                    if showCompletionBanner, let error = aiStore.completionError {
                        AICompletionBanner(error: error)
                            .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: showCompletionBanner)
                    }

                    if showingSearch {
                        GlobalSearchView(isPresented: $showingSearch)
                            .environment(sessionManager)
                            .padding(.top, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: showingSearch)
                            .zIndex(10)
                    }
                }
                .frame(minWidth: 400, minHeight: 200)
                .paneHighlight(.terminal, store: paneNav)

                if showChat, let session = sessionManager.activeSession {
                    ChatPanelView(session: session)
                        .id(session.id)
                        .frame(minHeight: 150, idealHeight: 260)
                        .paneHighlight(.chat, store: paneNav)
                }
            }

            if showHistory {
                HistorySidebarView()
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 400)
                    .paneHighlight(.history, store: paneNav)
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(Color.black)
        .sheet(isPresented: $showingAliases) {
            AliasManagerView()
                .environment(aliasStore)
        }
        .sheet(isPresented: $showingKeybindings) {
            KeybindingManagerView()
                .environment(keybindingStore)
        }
        .sheet(isPresented: $showingAISettings) {
            AISettingsView()
                .environment(aiStore)
        }
        // Notifications from menu items and keybinding monitor
        .onReceive(NotificationCenter.default.publisher(for: .openAliases))     { _ in showingAliases     = true }
        .onReceive(NotificationCenter.default.publisher(for: .openKeybindings)) { _ in showingKeybindings = true }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSessions))  { _ in showSessions.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleHistory))   { _ in showHistory.toggle()  }
        .onReceive(NotificationCenter.default.publisher(for: .toggleChat))      { _ in showChat.toggle()     }
        .onReceive(NotificationCenter.default.publisher(for: .newSession))      { _ in sessionManager.addSession() }
        .onReceive(NotificationCenter.default.publisher(for: .openAISettings))  { _ in showingAISettings  = true }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSearch))    { _ in showingSearch.toggle() }
        // Keep paneNav in sync with visible panes
        .onChange(of: showSessions) { _, vis in
            syncVisiblePanes()
            if !vis && paneNav.focusedPane == .sessions { paneNav.focusedPane = .terminal }
        }
        .onChange(of: showHistory) { _, vis in
            syncVisiblePanes()
            if !vis && paneNav.focusedPane == .history { paneNav.focusedPane = .terminal }
        }
        .onChange(of: showChat) { _, vis in
            syncVisiblePanes()
            if !vis && paneNav.focusedPane == .chat { paneNav.focusedPane = .terminal }
        }
        .onAppear { syncVisiblePanes() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showSessions.toggle() } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showSessions ? "Hide Sessions" : "Show Sessions")
            }

            ToolbarItem(placement: .primaryAction) {
                Button { showChat.toggle() } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .help(showChat ? "Hide Chat" : "Show Chat")
            }

            ToolbarItem(placement: .primaryAction) {
                Button { showHistory.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showHistory ? "Hide History" : "Show History")
            }
        }
    }

    private func syncVisiblePanes() {
        var panes: Set<PaneNavigationStore.Pane> = [.terminal]
        if showSessions { panes.insert(.sessions) }
        if showHistory  { panes.insert(.history) }
        if showChat     { panes.insert(.chat) }
        paneNav.visiblePanes = panes
    }
}

// MARK: - Pane highlight modifier

private struct PaneHighlightModifier: ViewModifier {
    let pane: PaneNavigationStore.Pane
    let store: PaneNavigationStore

    private var isHighlighted: Bool {
        store.isNavigating && store.focusedPane == pane
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
    }
}

extension View {
    func paneHighlight(_ pane: PaneNavigationStore.Pane, store: PaneNavigationStore) -> some View {
        modifier(PaneHighlightModifier(pane: pane, store: store))
    }
}
