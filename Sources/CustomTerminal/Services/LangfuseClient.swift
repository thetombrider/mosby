import Foundation

/// Thin REST client for Langfuse — prompt management + tracing.
/// Reads credentials automatically from a .env file (current working dir) or process environment.
actor LangfuseClient {
    static let shared = LangfuseClient()

    private let publicKey: String
    private let secretKey: String
    private let baseURL: String

    private init() {
        let dotEnv  = LangfuseClient.loadDotEnv()
        let procEnv = ProcessInfo.processInfo.environment

        func env(_ key: String) -> String { dotEnv[key] ?? procEnv[key] ?? "" }

        publicKey = env("LANGFUSE_PUBLIC_KEY")
        secretKey = env("LANGFUSE_SECRET_KEY")
        let raw   = env("LANGFUSE_BASE_URL")
        baseURL   = raw.isEmpty ? "https://cloud.langfuse.com" : raw
    }

    var isConfigured: Bool { !publicKey.isEmpty && !secretKey.isEmpty }

    private var authHeader: String {
        "Basic \(Data("\(publicKey):\(secretKey)".utf8).base64EncodedString())"
    }

    // MARK: - Prompt Management

    /// Fetch the production-labelled prompt. Returns nil on any failure; callers must fall back.
    func fetchPrompt(name: String) async -> (text: String, version: Int)? {
        guard isConfigured else { return nil }
        guard let url = URL(string: "\(baseURL)/api/public/v2/prompts/\(name)?label=production") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let prompt  = json["prompt"]  as? String,
                let version = json["version"] as? Int
            else { return nil }
            return (text: prompt, version: version)
        } catch {
            return nil
        }
    }

    // MARK: - Tracing

    /// Sends a trace + generation pair for a chat turn.
    func traceChatTurn(
        traceId: String,
        generationId: String,
        sessionId: String,
        userInput: String,
        messages: [[String: String]],   // full input sent to API (system + history)
        output: String,
        model: String,
        promptName: String,
        promptVersion: Int?,
        startTime: Date,
        endTime: Date
    ) async {
        guard isConfigured else { return }

        let iso = isoFormatter()
        let now  = iso.string(from: Date())
        let t0   = iso.string(from: startTime)
        let t1   = iso.string(from: endTime)

        let traceBody: [String: Any] = [
            "id":        traceId,
            "name":      "chat-turn",
            "sessionId": sessionId,
            "input":     ["role": "user", "content": userInput],
            "output":    output,
        ]

        var genBody: [String: Any] = [
            "id":              generationId,
            "traceId":         traceId,
            "name":            "chat-stream",
            "model":           model,
            "modelParameters": ["temperature": 0.1, "maxTokens": 1024],
            "input":           messages,
            "output":          output,
            "startTime":       t0,
            "endTime":         t1,
            "promptName":      promptName,
        ]
        if let v = promptVersion { genBody["promptVersion"] = v }

        await ingest([
            event("trace-create",      body: traceBody, timestamp: now),
            event("generation-create", body: genBody,   timestamp: now),
        ])
    }

    /// Sends a trace + generation pair for a command completion.
    func traceCommandCompletion(
        traceId: String,
        generationId: String,
        partial: String,
        output: String,
        model: String,
        promptName: String,
        promptVersion: Int?,
        startTime: Date,
        endTime: Date
    ) async {
        guard isConfigured else { return }

        let iso = isoFormatter()
        let now  = iso.string(from: Date())
        let t0   = iso.string(from: startTime)
        let t1   = iso.string(from: endTime)

        let traceBody: [String: Any] = [
            "id":     traceId,
            "name":   "command-completion",
            "input":  partial,
            "output": output,
        ]

        var genBody: [String: Any] = [
            "id":              generationId,
            "traceId":         traceId,
            "name":            "complete-command",
            "model":           model,
            "modelParameters": ["temperature": 0.1, "maxTokens": 128],
            "input":           [["role": "user", "content": "Complete: \(partial)"]],
            "output":          output,
            "startTime":       t0,
            "endTime":         t1,
            "promptName":      promptName,
        ]
        if let v = promptVersion { genBody["promptVersion"] = v }

        await ingest([
            event("trace-create",      body: traceBody, timestamp: now),
            event("generation-create", body: genBody,   timestamp: now),
        ])
    }

    // MARK: - Private helpers

    private func ingest(_ batch: [[String: Any]]) async {
        guard isConfigured, !batch.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/public/ingestion") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeader,    forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["batch": batch])
        _ = try? await URLSession.shared.data(for: req)
    }

    private func event(_ type: String, body: [String: Any], timestamp: String) -> [String: Any] {
        ["id": UUID().uuidString, "type": type, "timestamp": timestamp, "body": body]
    }

    private func isoFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    // MARK: - .env loader

    private static func loadDotEnv() -> [String: String] {
        let paths = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundleURL.deletingLastPathComponent().path + "/.env",
        ]
        for path in paths {
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var result: [String: String] = [:]
            for line in raw.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !t.hasPrefix("#"), let eqRange = t.range(of: "=") else { continue }
                let key = String(t[t.startIndex..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                var val = String(t[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) ||
                   (val.hasPrefix("'")  && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                if !key.isEmpty { result[key] = val }
            }
            return result
        }
        return [:]
    }
}
