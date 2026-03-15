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
        case table(headers: [String], rows: [[String]])
    }
    let kind: Kind
}

// MARK: - Parsing

private func parseTableRow(_ line: String) -> [String] {
    var cells = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
    if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
    if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

private func isSeparatorRow(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("|") else { return false }
    return trimmed.components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" } && $0.contains("-") }
}

/// Splits a plain-text block into text and table sub-segments.
private func splitTextAndTables(_ text: String) -> [MessageSegment] {
    let lines = text.components(separatedBy: "\n")
    var result: [MessageSegment] = []
    var textAccumulator: [String] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]
        let isTableLine = line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        let nextIsSeparator = i + 1 < lines.count && isSeparatorRow(lines[i + 1])

        if isTableLine && nextIsSeparator {
            // Flush accumulated text
            let accumulated = textAccumulator.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !accumulated.isEmpty {
                result.append(MessageSegment(kind: .text(accumulated)))
            }
            textAccumulator = []

            let headers = parseTableRow(line)
            i += 2 // skip header + separator

            var rows: [[String]] = []
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                rows.append(parseTableRow(lines[i]))
                i += 1
            }
            result.append(MessageSegment(kind: .table(headers: headers, rows: rows)))
        } else {
            textAccumulator.append(line)
            i += 1
        }
    }

    let remaining = textAccumulator.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if !remaining.isEmpty {
        result.append(MessageSegment(kind: .text(remaining)))
    }

    return result
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
                segments.append(contentsOf: splitTextAndTables(trimmed))
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
                    segments.append(contentsOf: splitTextAndTables(rest))
                }
                break
            }
        } else {
            let rest = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                segments.append(contentsOf: splitTextAndTables(rest))
            }
            break
        }
    }

    return segments
}

// MARK: - PreferenceKey for text bubble width

private struct TextBubbleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Markdown helpers

/// Parses markdown inline formatting (bold, italic, code, links) while preserving
/// every newline as a real line break in the resulting AttributedString.
/// Foundation's markdown parser does not implement CommonMark hard-line-breaks
/// (trailing-space + \n), so we split on \n, parse each line independently,
/// and rejoin with literal \n characters that SwiftUI Text always honours.
private func makeAttributedString(_ text: String) -> AttributedString {
    let lines = text.components(separatedBy: "\n")
    var result = AttributedString()
    for (i, line) in lines.enumerated() {
        let parsed = (try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(line)
        result += parsed
        if i < lines.count - 1 {
            result += AttributedString("\n")
        }
    }
    return result
}

// MARK: - Assistant message

private struct AssistantMessageView: View {
    let content: String
    let session: TerminalSession

    @State private var textBubbleWidth: CGFloat = 0

    private var segments: [MessageSegment] { parseSegments(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .text(let text):
                    let attributed = makeAttributedString(text)
                    Text(attributed)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            GeometryReader { geo in
                                Color.white.opacity(0.08)
                                    .preference(key: TextBubbleWidthKey.self, value: geo.size.width)
                            }
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .font(.system(size: 12))
                case .code(let language, let body):
                    CodeBlockView(language: language, code: body, session: session)
                        .frame(maxWidth: textBubbleWidth > 0 ? textBubbleWidth : .infinity, alignment: .leading)
                case .table(let headers, let rows):
                    TableView(headers: headers, rows: rows)
                }
            }
        }
        .onPreferenceChange(TextBubbleWidthKey.self) { width in
            if width > 0 { textBubbleWidth = width }
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
                // space for Run button overlay
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)
            .overlay(alignment: .trailing) {
                Button {
                    session.injectText(code)
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.trailing, 10)
            }

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

// MARK: - Table

private struct TableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            TableRowView(cells: headers, isHeader: true, columnCount: headers.count)

            Divider()
                .overlay(Color.white.opacity(0.2))

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIdx in
                TableRowView(
                    cells: rows[rowIdx],
                    isHeader: false,
                    columnCount: headers.count,
                    isAlternate: rowIdx % 2 == 1
                )
                if rowIdx < rows.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.07))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct TableRowView: View {
    let cells: [String]
    let isHeader: Bool
    let columnCount: Int
    var isAlternate: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                let cell = col < cells.count ? cells[col] : ""
                let cellAttributed = (try? AttributedString(
                    markdown: cell,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(cell)
                Text(cellAttributed)
                    .font(.system(size: 11, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? .white : .white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if col < columnCount - 1 {
                    Divider()
                        .overlay(Color.white.opacity(isHeader ? 0.15 : 0.08))
                }
            }
        }
        .background(isHeader ? Color.white.opacity(0.12) : (isAlternate ? Color.white.opacity(0.04) : Color.clear))
    }
}
