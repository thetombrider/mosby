import SwiftUI
import AppKit

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    @Binding var isPresented: Bool

    @Environment(SessionManager.self)  private var sessionManager
    @Environment(AliasStore.self)      private var aliasStore

    @State private var service = CommandPaletteService()
    @State private var scrollDirection: ScrollDirection = .none

    private enum ScrollDirection { case none, up, down }

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap anywhere to dismiss
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Palette panel
            VStack(spacing: 0) {
                searchBar
                Divider().background(Color.white.opacity(0.1))
                resultsList
                Divider().background(Color.white.opacity(0.08))
                footer
            }
            .frame(width: 620)
            .frame(maxHeight: 500)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.6), radius: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -60) // slightly above center, Spotlight-style
        }
        .onAppear {
            service.search(
                sessions: sessionManager.sessions,
                history: sessionManager.globalHistory.entries,
                aliases: aliasStore.aliases
            )
        }
        .onChange(of: service.query) { refresh() }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: searchIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            PaletteSearchField(
                text: $service.query,
                placeholder: searchPlaceholder,
                onUpArrow:   { scrollDirection = .up;   service.moveSelection(by: -1) },
                onDownArrow: { scrollDirection = .down; service.moveSelection(by: +1) },
                onSubmit:    { executeSelected() },
                onEscape:    { dismiss() }
            )
            .font(.system(size: 16))

            if service.isSearching {
                ProgressView().controlSize(.small)
            } else if !service.results.isEmpty && !service.query.isEmpty {
                Text(resultCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        if service.results.isEmpty && !service.isSearching {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedResults, id: \.category) { group in
                            Text(group.category.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 3)

                            ForEach(group.results.enumerated(), id: \.element.id) { offset, result in
                                let globalIdx = group.startIndex + offset
                                ResultRow(
                                    result: result,
                                    isSelected: globalIdx == service.selectedIndex,
                                    query: effectiveTerm
                                )
                                .id(result.id)
                                .onTapGesture { execute(result) }
                                .onHover { hovering in
                                    if hovering { service.selectedIndex = globalIdx }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: service.selectedIndex) { _, idx in
                    guard scrollDirection != .none else { return }
                    let dir = scrollDirection
                    scrollDirection = .none
                    guard let result = service.results[safe: idx] else { return }
                    let anchor: UnitPoint = (dir == .down) ? .bottom : .top
                    proxy.scrollTo(result.id, anchor: anchor)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(service.query.isEmpty ? "Sessions, history, and actions" : "No results")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hintLabel(icon: "return", text: "select")
            hintLabel(icon: "arrow.up.arrow.down", text: "navigate")
            hintLabel(icon: "escape", text: "dismiss")
            Spacer()
            filterHints
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var filterHints: some View {
        HStack(spacing: 8) {
            filterPill(prefix: ">", label: "actions")
            filterPill(prefix: "@", label: "sessions")
            filterPill(prefix: "!", label: "history")
            filterPill(prefix: "/", label: "output")
        }
    }

    private func hintLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func filterPill(prefix: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(prefix)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Grouping

    private struct ResultGroup {
        let category: String
        let results: [PaletteResult]
        let startIndex: Int
    }

    private var groupedResults: [ResultGroup] {
        var groups: [ResultGroup] = []
        var cursor = 0
        let categories = orderedCategories

        for category in categories {
            let hits = service.results.enumerated().filter { $0.element.category == category }
            guard !hits.isEmpty else { continue }
            groups.append(ResultGroup(
                category: category,
                results: hits.map(\.element),
                startIndex: cursor
            ))
            cursor += hits.count
        }
        return groups
    }

    private let orderedCategories = ["Sessions", "Actions", "History", "Aliases", "Terminal Output"]

    // MARK: - Execution

    private func executeSelected() {
        guard let result = service.selectedResult else { return }
        execute(result)
    }

    private func execute(_ result: PaletteResult) {
        switch result {
        case .session(let s):
            sessionManager.activeSessionId = s.id
            dismiss()

        case .history(let h):
            dismiss()
            sessionManager.activeSession?.terminalView.send(txt: h.command + "\n")

        case .alias(let a):
            dismiss()
            sessionManager.activeSession?.terminalView.send(txt: a.command + "\n")

        case .action(let a):
            dismiss()
            if let name = a.notificationName {
                NotificationCenter.default.post(name: name, object: nil)
            }

        case .match(let m):
            dismiss()
            sessionManager.activeSessionId = m.session.id
            let tv = m.session.terminalView
            tv.clearSearch()
            for _ in 0...m.matchIndexInSession {
                tv.findNext(effectiveTerm, options: .init(caseSensitive: false), scrollToResult: true)
            }
        }
    }

    // MARK: - Helpers

    private func dismiss() {
        service.clear()
        isPresented = false
    }

    private func refresh() {
        service.search(
            sessions: sessionManager.sessions,
            history: sessionManager.globalHistory.entries,
            aliases: aliasStore.aliases
        )
    }

    private var effectiveTerm: String {
        let (_, term) = CommandPaletteService.Filter.parse(service.query.trimmingCharacters(in: .whitespaces))
        return term
    }

    private var searchIcon: String {
        let raw = service.query.trimmingCharacters(in: .whitespaces)
        guard let first = raw.first else { return "magnifyingglass" }
        switch first {
        case ">": return "command"
        case "@": return "terminal"
        case "!": return "clock"
        case "#": return "at"
        case "/": return "doc.text.magnifyingglass"
        default:  return "magnifyingglass"
        }
    }

    private var searchPlaceholder: String {
        "Search or type > @ ! # / for filters…"
    }

    private var resultCountText: String {
        let n = service.results.count
        return n == 1 ? "1 result" : "\(n) results"
    }
}

// MARK: - ResultRow

private struct ResultRow: View {
    let result: PaletteResult
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                if case .match(let m) = result, !query.isEmpty {
                    Text(highlightedText(m.lineText, query: query))
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(result.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }

                if let sub = result.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.25)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
    }

    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .init(.init(white: 1, alpha: 0.22))
                attributed[attrRange].foregroundColor = .white
            }
            start = range.upperBound
        }
        return attributed
    }
}

// MARK: - PaletteSearchField (custom NSTextField for arrow-key interception)

private struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onUpArrow:   () -> Void
    let onDownArrow: () -> Void
    let onSubmit:    () -> Void
    let onEscape:    () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ArrowTextField {
        let tf = ArrowTextField()
        tf.isBezeled        = false
        tf.drawsBackground  = false
        tf.focusRingType    = .none
        tf.font             = .systemFont(ofSize: 16)
        tf.textColor        = .labelColor
        tf.placeholderString = placeholder
        tf.delegate         = context.coordinator
        tf.onUpArrow        = onUpArrow
        tf.onDownArrow      = onDownArrow
        tf.onSubmit         = onSubmit
        tf.onEscape         = onEscape
        DispatchQueue.main.async { tf.window?.makeFirstResponder(tf) }
        return tf
    }

    func updateNSView(_ nsView: ArrowTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField
        init(_ parent: PaletteSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onUpArrow()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onDownArrow()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }

    // MARK: ArrowTextField

    final class ArrowTextField: NSTextField {
        var onUpArrow:   (() -> Void)?
        var onDownArrow: (() -> Void)?
        var onSubmit:    (() -> Void)?
        var onEscape:    (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onUpArrow?()    // ↑
            case 125: onDownArrow?()  // ↓
            case 36:  onSubmit?()     // Return
            case 53:  onEscape?()     // Escape
            default:  super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
