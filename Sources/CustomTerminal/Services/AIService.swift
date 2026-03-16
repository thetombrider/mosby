import Foundation

enum AIServiceError: Error, LocalizedError {
    case noAPIKey
    case httpError(Int, String)
    case decodingError
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter API key not set. Open Terminal > AI Settings."
        case .httpError(let code, let body):
            return "API error \(code): \(body.prefix(120))"
        case .decodingError:
            return "Unexpected API response format."
        case .emptyInput:
            return "Nothing to complete."
        }
    }
}

enum AIService {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    struct ChatTurn {
        let role: String
        let content: String
    }

    // MARK: - Default system prompts (used as fallback when Langfuse is unavailable)

    static let defaultChatSystemPrompt = """
    You are a helpful terminal assistant embedded in Mosby, a macOS terminal emulator. \
    Always reply in the language of the user. \
    Help the user with shell commands, explain errors, and assist with their work in the current session. \
    When suggesting a shell command, wrap it in a fenced code block:
    ```sh
    command-here
    ```
    """

    static let defaultCompletionSystemPrompt = """
    You are a shell autocomplete engine. \
    Given a partial shell command, output the COMPLETE command (starting from the beginning). \
    Output ONLY the completed command — no explanation, no markdown, no backticks. \
    One line only. Keep it the most common/practical interpretation.
    """

    // MARK: - System prompt builder

    /// Assembles the full chat system prompt from a base template and runtime context.
    static func buildChatSystemPrompt(
        base: String,
        currentDirectory: String,
        directoryContents: [String],
        recentCommands: [String],
        terminalLines: [String]
    ) -> String {
        var system = base
        if !currentDirectory.isEmpty {
            system += "\n\nCurrent working directory: \(currentDirectory)"
            if !directoryContents.isEmpty {
                system += "\nDirectory contents: \(directoryContents.sorted().joined(separator: "  "))"
            }
        }
        if !recentCommands.isEmpty {
            system += "\n\nCommand history (most recent last):\n\(recentCommands.reversed().joined(separator: "\n"))"
        }
        if !terminalLines.isEmpty {
            system += "\n\nVisible terminal output:\n\(terminalLines.joined(separator: "\n"))"
        }
        return system
    }

    // MARK: - Chat stream

    /// Multi-turn chat — streams token deltas.
    /// `systemPrompt` is the fully assembled system prompt (use `buildChatSystemPrompt` to construct it).
    static func chatStream(
        messages: [ChatTurn],
        systemPrompt: String,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else { throw AIServiceError.noAPIKey }

                    var apiMessages: [[String: String]] = [["role": "system", "content": systemPrompt]]
                    for turn in messages { apiMessages.append(["role": turn.role, "content": turn.content]) }

                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Mosby", forHTTPHeaderField: "X-Title")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "messages": apiMessages,
                        "max_tokens": 1024, "temperature": 0.1, "stream": true,
                    ] as [String: Any])

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 512 { break }
                        }
                        throw AIServiceError.httpError(http.statusCode, String(data: errorData, encoding: .utf8) ?? "")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        guard
                            let data    = payload.data(using: .utf8),
                            let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = obj["choices"] as? [[String: Any]],
                            let delta   = choices.first?["delta"] as? [String: Any],
                            let token   = delta["content"] as? String
                        else { continue }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Command completion

    /// Suggest a completion for a partial command already typed at the prompt.
    /// `systemPromptOverride` replaces the default autocomplete system prompt when provided.
    static func completeCommand(
        partial: String,
        history: [String],
        apiKey: String,
        model: String,
        systemPromptOverride: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.noAPIKey }
        let trimmed = partial.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw AIServiceError.emptyInput }

        let system = systemPromptOverride ?? defaultCompletionSystemPrompt

        var messages: [[String: String]] = [["role": "system", "content": system]]

        let recentHistory = history.prefix(8).reversed().joined(separator: "\n")
        if !recentHistory.isEmpty {
            messages.append(["role": "user",      "content": "Recent commands:\n\(recentHistory)"])
            messages.append(["role": "assistant", "content": "Noted."])
        }

        messages.append(["role": "user", "content": "Complete: \(partial)"])

        return try await call(messages: messages, apiKey: apiKey, model: model, maxTokens: 128)
    }

    // MARK: - Private

    private static func call(
        messages: [[String: String]],
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mosby", forHTTPHeaderField: "X-Title")

        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages,
            "max_tokens": maxTokens, "temperature": 0.1,
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.httpError(http.statusCode, body)
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIServiceError.decodingError }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
