import AppKit
import Observation
import SwiftTerm

// MARK: - TrackedLocalProcessTerminalView

/// Subclass of LocalProcessTerminalView that intercepts user input to track commands.
final class TrackedLocalProcessTerminalView: LocalProcessTerminalView {

    /// True when a subprocess (e.g. claude, vim) is in the foreground, not the shell itself.
    var isSubprocessRunning: Bool {
        guard let proc = process else { return false }
        return tcgetpgrp(proc.childfd) != getpgid(proc.shellPid)
    }

    /// Called whenever the user submits a command (text before Enter).
    var onCommandSubmitted: ((String) -> Void)?

    /// Optional alias store — when set, alias names typed at the prompt are expanded.
    var aliasStore: AliasStore?

    var inputBuffer = ""

    /// Number of characters currently "selected" — the cursor has been moved this many
    /// positions to the left of the end of inputBuffer via Cmd+Arrow selection.
    var inputSelectionLength: Int = 0

    /// The text the user has typed since the last prompt (read by AI completion).
    var currentInputBuffer: String { inputBuffer }

    /// Resets the tracked input buffer (called after AI injection so the next
    /// completion request starts from a clean slate).
    func resetInputBuffer() {
        inputBuffer = ""
        inputSelectionLength = 0
    }

    // MARK: - Ghost text overlay

    private var ghostTextField: NSTextField?

    /// Show ghost text (the AI suggestion suffix) inline at the cursor position.
    func showGhostText(_ suffix: String) {
        guard !suffix.isEmpty else { hideGhostText(); return }

        let tf: NSTextField
        if let existing = ghostTextField {
            tf = existing
        } else {
            tf = NSTextField(labelWithString: "")
            tf.isEditable = false
            tf.isBezeled = false
            tf.drawsBackground = false
            ghostTextField = tf
        }

        tf.font = self.font
        tf.stringValue = suffix
        tf.textColor = NSColor(white: 1.0, alpha: 0.35)
        tf.sizeToFit()

        if let caretView = findCaretView() {
            let targetSuperview = caretView.superview ?? self
            if tf.superview !== targetSuperview {
                tf.removeFromSuperview()
                targetSuperview.addSubview(tf)
            }
            let cr = caretView.frame
            tf.frame = CGRect(x: cr.maxX, y: cr.minY, width: tf.frame.width, height: cr.height)
        }

        tf.isHidden = false
    }

    func hideGhostText() {
        ghostTextField?.isHidden = true
    }

    private func findCaretView() -> NSView? {
        func search(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)).lowercased().contains("caret") { return view }
            for sub in view.subviews { if let found = search(sub) { return found } }
            return nil
        }
        return search(self)
    }

    /// Sends bytes directly to the PTY, bypassing the input-tracking override.
    /// Used for cursor-movement sequences so they don't corrupt `inputBuffer`.
    func sendRaw(_ bytes: [UInt8]) {
        super.send(source: self, data: ArraySlice(bytes))
    }

    // MARK: - Selection

    /// Move cursor to the start of the input line, selecting all text to the left.
    func selectToLineStart() {
        let toMove = inputBuffer.count - inputSelectionLength
        guard toMove > 0 else { return }
        var bytes: [UInt8] = []
        for _ in 0..<toMove { bytes += [0x1b, 0x5b, 0x44] } // N × Left arrow
        sendRaw(bytes)
        inputSelectionLength = inputBuffer.count
    }

    /// Collapse the selection by moving the cursor back to the end of the input line.
    func selectToLineEnd() {
        guard inputSelectionLength > 0 else { return }
        var bytes: [UInt8] = []
        for _ in 0..<inputSelectionLength { bytes += [0x1b, 0x5b, 0x43] } // N × Right arrow
        sendRaw(bytes)
        inputSelectionLength = 0
    }

    /// Delete the currently selected text (cursor is at start of selection,
    /// so send N forward-deletes to erase chars to the right).
    func deleteSelection() {
        guard inputSelectionLength > 0 else { return }
        let count = inputSelectionLength
        // Remove the selected chars from the tail of inputBuffer
        if inputBuffer.count >= count {
            inputBuffer.removeLast(count)
        } else {
            inputBuffer = ""
        }
        // Send N × forward-delete (ESC [ 3 ~) to the shell
        var bytes: [UInt8] = []
        for _ in 0..<count { bytes += [0x1b, 0x5b, 0x33, 0x7e] }
        sendRaw(bytes)
        inputSelectionLength = 0
    }

    /// `send` is called (from TerminalViewDelegate) when the user sends keystrokes
    /// to the child process. We parse it here to extract submitted commands.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let str = String(bytes: data, encoding: .utf8) else {
            super.send(source: source, data: data)
            return
        }

        // Any direct keystroke cancels the active selection.
        inputSelectionLength = 0

        var isEnter  = false
        var inEscape = false   // saw ESC, waiting for sequence type
        var inCSI    = false   // inside CSI (ESC [), waiting for final byte
        let prevBuffer = inputBuffer

        for scalar in str.unicodeScalars {
            let v = scalar.value

            // ── Escape-sequence filter ───────────────────────────────────────
            // Arrow keys, terminal queries, etc. arrive as ESC [ ... <final>.
            // ESC (0x1b) itself falls below 0x20 and is silently dropped, but
            // the '[', letters and digits that follow are printable and would
            // corrupt inputBuffer without this filter.
            if inEscape {
                if inCSI {
                    // CSI final byte is in 0x40–0x7E; anything else is a parameter.
                    if v >= 0x40 && v <= 0x7e { inEscape = false; inCSI = false }
                } else if v == 0x5b {   // '[' → CSI sequence
                    inCSI = true
                } else {                // Other single-char ESC sequence
                    inEscape = false
                }
                continue
            }
            if v == 0x1b { inEscape = true; continue }
            // ────────────────────────────────────────────────────────────────

            switch v {
            case 0x0d, 0x0a:
                isEnter = true
            case 0x7f, 0x08:
                if !inputBuffer.isEmpty { inputBuffer.removeLast() }
            case 0x03, 0x04:
                inputBuffer = ""
            case 0x20..<0x7f:
                inputBuffer.append(Character(scalar))
            default:
                break
            }
        }

        if isEnter {
            hideGhostText()
            NotificationCenter.default.post(name: .terminalInputChanged, object: self)
        } else if inputBuffer != prevBuffer {
            NotificationCenter.default.post(name: .terminalInputChanged, object: self)
        }

        if isEnter {
            let cmd = inputBuffer.trimmingCharacters(in: .whitespaces)
            inputBuffer = ""

            // Only record to history when the shell itself is the foreground process.
            // Inside a subprocess (claude, vim, python REPL, etc.) tcgetpgrp returns
            // a different process group, so we skip the history callback entirely.
            let isAtShellPrompt: Bool = {
                guard let proc = self.process else { return true }
                return tcgetpgrp(proc.childfd) == getpgid(proc.shellPid)
            }()

            if !cmd.isEmpty, let expanded = aliasStore?.expand(cmd) {
                // Clear the typed alias with Ctrl-U, then send the expanded command.
                let replacement = "\u{0015}" + expanded + "\r"
                let bytes = [UInt8](replacement.utf8)
                super.send(source: source, data: bytes[...])
                if isAtShellPrompt { onCommandSubmitted?(expanded) }
            } else {
                super.send(source: source, data: data)
                if !cmd.isEmpty && isAtShellPrompt { onCommandSubmitted?(cmd) }
            }
        } else {
            super.send(source: source, data: data)
        }
    }
}

// MARK: - TerminalSession

/// Wraps a TrackedLocalProcessTerminalView with session metadata and command history.
@Observable
final class TerminalSession: NSObject {

    // MARK: - Process status

    enum ProcessStatus {
        /// Shell prompt is active, no subprocess running.
        case idle
        /// A subprocess (e.g. claude, make, vim) is in the foreground.
        case running
        /// Subprocess finished while this session was not the active one.
        case needsAttention
        /// The shell process itself has terminated.
        case dead
    }

    var processStatus: ProcessStatus = .idle
    private var wasRunning = false

    /// Snapshot the subprocess state. Call periodically from outside (e.g. a timer in SessionManager).
    /// `isActive` should be true only for the session the user is currently viewing.
    func refreshProcessStatus(isActive: Bool) {
        guard isAlive else { processStatus = .dead; return }
        let running = terminalView.isSubprocessRunning
        defer { wasRunning = running }

        if running {
            processStatus = .running
        } else if wasRunning && !isActive {
            // Just finished while the user wasn't watching → flag it.
            processStatus = .needsAttention
        } else if isActive {
            // User switched to this session — always clear the badge.
            processStatus = running ? .running : .idle
        }
        // Otherwise keep current status (idle stays idle, needsAttention persists until active).
    }

    let id: UUID
    var name: String
    var isAlive: Bool = true

    /// Current working directory, updated via OSC 7 shell integration.
    /// Nil until the shell emits its first OSC 7 sequence.
    var currentDirectory: String? = nil

    /// Global history shared across all sessions. Injected by SessionManager after init.
    var globalHistory: GlobalHistoryStore?

    /// Convenience accessor so existing callers (AI features etc.) keep working.
    var commandHistory: [HistoryEntry] { globalHistory?.entries ?? [] }

    /// The actual terminal emulator view. Kept alive here so SwiftUI can swap it without
    /// destroying the underlying PTY.
    let terminalView: TrackedLocalProcessTerminalView

    struct HistoryEntry: Identifiable, Codable {
        let id        : UUID
        let command   : String
        let timestamp : Date

        init(command: String, timestamp: Date) {
            self.id        = UUID()
            self.command   = command
            self.timestamp = timestamp
        }
    }

    /// Called when the session name changes (e.g. from a terminal title update).
    var onNameChanged: (() -> Void)?

    init(id: UUID = UUID(), name: String, aliasStore: AliasStore? = nil) {
        self.id   = id
        self.name = name
        self.terminalView = TrackedLocalProcessTerminalView(frame: .zero)
        super.init()

        terminalView.aliasStore = aliasStore
        terminalView.processDelegate = self
        terminalView.onCommandSubmitted = { [weak self] cmd in
            guard let self else { return }
            let entry = HistoryEntry(command: cmd, timestamp: Date.now)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.globalHistory?.append(entry)
            }
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let execName = "-" + URL(fileURLWithPath: shell).lastPathComponent
        terminalView.startProcess(executable: shell, execName: execName)
    }

    /// Injects a command into the terminal (used by history sidebar re-run).
    func inject(command: String) {
        terminalView.send(txt: command + "\n")
    }

    /// Clears the current prompt line and types `text` (does NOT press Enter).
    /// Used by AI features to place a generated or completed command at the prompt.
    func injectText(_ text: String) {
        // \u{0015} = Ctrl-U, which clears the current line in most shells.
        terminalView.send(txt: "\u{0015}" + text)
        terminalView.resetInputBuffer()
    }

    var currentInputBuffer: String { terminalView.currentInputBuffer }

    /// Extracts all non-empty lines from the terminal scrollback buffer.
    /// Safe to call from a background thread — reads immutable buffer state.
    func extractBufferLines() -> [(row: Int, text: String)] {
        guard let terminal = terminalView.terminal else { return [] }
        var result: [(Int, String)] = []
        var trailingNils = 0

        // getScrollInvariantLine returns nil for evicted rows (before linesTop) and
        // rows beyond the buffer end. We stop once we've seen rows+1 consecutive nils
        // after finding content, which reliably marks the end of the buffer.
        // The 10_000 cap prevents any runaway iteration.
        for row in 0..<10_000 {
            if let line = terminal.getScrollInvariantLine(row: row) {
                trailingNils = 0
                let text = line.translateToString(trimRight: true)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append((row, text))
                }
            } else {
                trailingNils += 1
                if !result.isEmpty && trailingNils > terminal.rows {
                    break
                }
            }
        }
        return result
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalSession: LocalProcessTerminalViewDelegate {

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.name = t
            self.onNameChanged?()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        // OSC 7 delivers "file://hostname/path" — extract the path component
        let path: String
        if let url = URL(string: directory), url.scheme == "file" {
            path = url.path
        } else {
            path = directory
        }
        guard !path.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.currentDirectory = path
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAlive = false
            self.name    = self.name + " (done)"
        }
    }
}
