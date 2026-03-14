import AppKit

enum TerminalAction: String, CaseIterable, Codable {
    case newSession
    case toggleSessions
    case toggleHistory
    case toggleSearch
    case toggleChat
    case openAliases
    case openKeybindings
    case aiComplete
    case selectToLineStart
    case selectToLineEnd

    var displayName: String {
        switch self {
        case .newSession:        "New Session"
        case .toggleSessions:   "Toggle Sessions Panel"
        case .toggleHistory:    "Toggle History Panel"
        case .toggleSearch:     "Toggle Search"
        case .toggleChat:       "Toggle Chat Panel"
        case .openAliases:      "Manage Aliases"
        case .openKeybindings:  "Manage Keybindings"
        case .aiComplete:       "AI: Complete Command"
        case .selectToLineStart: "Move to Line Start"
        case .selectToLineEnd:  "Move to Line End"
        }
    }

    /// Notification to post when this action fires. Nil for actions handled directly
    /// in the keyboard forwarder (no notification listener needed).
    var notificationName: Notification.Name? {
        switch self {
        case .newSession:        .newSession
        case .toggleSessions:   .toggleSessions
        case .toggleHistory:    .toggleHistory
        case .toggleSearch:     .toggleSearch
        case .toggleChat:       .toggleChat
        case .openAliases:      .openAliases
        case .openKeybindings:  .openKeybindings
        case .aiComplete:       nil
        case .selectToLineStart: nil
        case .selectToLineEnd:  nil
        }
    }

    var defaultCombo: KeyCombo {
        let cmd      = NSEvent.ModifierFlags.command.rawValue
        let cmdShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let opt      = NSEvent.ModifierFlags.option.rawValue
        return switch self {
        // Key codes: T=17, 1=18, 2=19, 3=20, A=0, K=40, G=5, F=3, Tab=48, Left=123, Right=124
        case .newSession:        KeyCombo(keyCode: 17,  modifiers: cmd,      display: "⌘T")
        case .toggleSessions:    KeyCombo(keyCode: 18,  modifiers: cmdShift, display: "⌘⇧1")
        case .toggleHistory:     KeyCombo(keyCode: 19,  modifiers: cmdShift, display: "⌘⇧2")
        case .toggleChat:        KeyCombo(keyCode: 20,  modifiers: cmdShift, display: "⌘⇧3")
        case .toggleSearch:      KeyCombo(keyCode: 3,   modifiers: cmd,      display: "⌘F")
        case .openAliases:       KeyCombo(keyCode: 0,   modifiers: cmdShift, display: "⌘⇧A")
        case .openKeybindings:   KeyCombo(keyCode: 40,  modifiers: cmdShift, display: "⌘⇧K")
        case .aiComplete:        KeyCombo(keyCode: 48,  modifiers: opt,      display: "⌥Tab")
        case .selectToLineStart: KeyCombo(keyCode: 123, modifiers: cmd,      display: "⌘←")
        case .selectToLineEnd:   KeyCombo(keyCode: 124, modifiers: cmd,      display: "⌘→")
        }
    }
}
