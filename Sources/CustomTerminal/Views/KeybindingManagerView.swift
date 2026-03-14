import SwiftUI
import AppKit

// MARK: - KeybindingManagerView

struct KeybindingManagerView: View {

    @Environment(KeybindingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var recordingAction: TerminalAction?

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Keybindings")
                    .font(.title2.bold())
                Spacer()
                Button("Reset All") { store.resetAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .padding(.trailing, 8)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Dismiss")
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(TerminalAction.allCases, id: \.rawValue) { action in
                        KeybindingRow(
                            action: action,
                            combo: store.combo(for: action),
                            isRecording: recordingAction == action,
                            onStartRecording: { recordingAction = action },
                            onSave: { combo in
                                store.set(combo: combo, for: action)
                                recordingAction = nil
                            },
                            onReset:  { store.reset(action: action); recordingAction = nil },
                            onCancel: { recordingAction = nil }
                        )
                        if action != TerminalAction.allCases.last {
                            Divider().opacity(0.3).padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider().opacity(0.3)

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Avoid macOS system shortcuts (⌘H, ⌘M, ⌘Q, ⌘Tab) — they are intercepted before reaching the app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 460, height: 500)
    }
}

// MARK: - Row

private struct KeybindingRow: View {

    let action: TerminalAction
    let combo: KeyCombo
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onSave: (KeyCombo) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(action.displayName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRecording {
                KeyRecorderView(onSave: onSave, onCancel: onCancel)
                    .frame(width: 130, height: 26)
            } else {
                Button(action: onStartRecording) {
                    Text(combo.display)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Current shortcut: \(combo.display). Tap to record new shortcut.")

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset to default")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Key recorder (AppKit bridge)

struct KeyRecorderView: NSViewRepresentable {
    let onSave: (KeyCombo) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let v = KeyRecorderNSView()
        v.onSave   = onSave
        v.onCancel = onCancel
        return v
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        Task { @MainActor in nsView.window?.makeFirstResponder(nsView) }
    }
}

class KeyRecorderNSView: NSView {
    var onSave:   ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        let text = "Press keys…" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ]
        let sz = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                              y: (bounds.height - sz.height) / 2),
                  withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }   // Escape — cancel
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let display = modSymbols(mods) + (event.charactersIgnoringModifiers?.uppercased() ?? "?")
        onSave?(KeyCombo(keyCode: event.keyCode, modifiers: mods.rawValue, display: display))
    }

    private func modSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }
}
