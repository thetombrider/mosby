import SwiftUI

/// Tracks keyboard-driven pane navigation (ESC → arrows → Enter).
@Observable
final class PaneNavigationStore {

    enum Pane: Equatable, CaseIterable {
        case sessions, terminal, chat, history
    }

    /// Whether the user is in "pane navigation" mode (borders shown, arrows move focus).
    var isNavigating = false

    /// The pane currently highlighted while navigating.
    var focusedPane: Pane = .terminal

    /// The pane the user is currently working in (after pressing Enter to dive in).
    var activePane: Pane = .terminal

    /// Which panes are currently visible (updated by ContentView).
    var visiblePanes: Set<Pane> = [.sessions, .terminal, .chat, .history]

    // MARK: - Actions

    /// Enter navigation mode, highlighting the given pane (default: terminal).
    func enterNavigation(currentPane: Pane = .terminal) {
        focusedPane = currentPane
        isNavigating = true
    }

    /// Exit navigation mode (user pressed Enter to dive into a pane, or ESC to dismiss).
    func exitNavigation() {
        isNavigating = false
    }

    /// Move focus in the given direction. Layout:
    /// ```
    /// [sessions] | [terminal] | [history]
    ///            | [chat]     |
    /// ```
    /// Skips hidden panes automatically.
    func move(_ direction: Direction) {
        let candidate: Pane?
        switch direction {
        case .left:
            switch focusedPane {
            case .terminal, .chat:
                candidate = visiblePanes.contains(.sessions) ? .sessions : nil
            case .history:
                candidate = .terminal  // terminal is always visible
            case .sessions:
                candidate = nil
            }
        case .right:
            switch focusedPane {
            case .sessions:
                candidate = .terminal
            case .terminal, .chat:
                candidate = visiblePanes.contains(.history) ? .history : nil
            case .history:
                candidate = nil
            }
        case .up:
            candidate = focusedPane == .chat ? .terminal : nil
        case .down:
            candidate = (focusedPane == .terminal && visiblePanes.contains(.chat)) ? .chat : nil
        }
        if let next = candidate { focusedPane = next }
    }

    enum Direction { case left, right, up, down }
}
