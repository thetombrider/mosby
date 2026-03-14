import SwiftUI
import AppKit
import SwiftTerm

/// NSViewRepresentable that hosts every session's terminal view simultaneously.
/// Only the active one is visible; the others are hidden but the PTY keeps running.
struct TerminalContainerView: NSViewRepresentable {

    let sessionManager: SessionManager

    final class Coordinator {
        var addedIds    = Set<UUID>()
        var lastFocused : UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        return v
    }

    func updateNSView(_ container: NSView, context: Context) {
        let c = context.coordinator

        // 1. Add views for new sessions
        for session in sessionManager.sessions {
            guard !c.addedIds.contains(session.id) else { continue }
            c.addedIds.insert(session.id)

            let tv = session.terminalView
            tv.identifier = NSUserInterfaceItemIdentifier(session.id.uuidString)
            tv.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.topAnchor    .constraint(equalTo: container.topAnchor),
                tv.bottomAnchor .constraint(equalTo: container.bottomAnchor),
                tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        // 2. Remove views for closed sessions
        let liveIds = Set(sessionManager.sessions.map { $0.id })
        for id in c.addedIds where !liveIds.contains(id) {
            container.subviews
                .first { $0.identifier?.rawValue == id.uuidString }?
                .removeFromSuperview()
            c.addedIds.remove(id)
        }

        // 3. Show only the active session
        for session in sessionManager.sessions {
            session.terminalView.isHidden = (session.id != sessionManager.activeSessionId)
        }

        // 4. Re-focus when the active session changes
        if c.lastFocused != sessionManager.activeSessionId {
            c.lastFocused = sessionManager.activeSessionId
            Task { @MainActor in
                sessionManager.activeSession?.terminalView.window?
                    .makeFirstResponder(sessionManager.activeSession?.terminalView)
            }
        }
    }
}
