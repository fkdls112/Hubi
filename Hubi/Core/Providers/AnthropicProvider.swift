import Foundation

/// Anthropic Messages API
/// 路径 /v1/messages，请求/事件流格式与 OpenAI 不同
struct AnthropicProvider: LLMProvider {
    let key: String = "anthropic"
    let displayName: String = "Anthropic Claude"
    var capabilities: Set<LLMCapability> = [.streaming, .toolCalling, .vision, .reasoning]
    let defaultBaseURL: String = "https://api.anthropic.com"

    func stream(request: ChatRequest, baseURL: String, apiKey: String?)
        -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runStream(request: request, baseURL: baseURL,
                                        apiKey: apiKey, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(request: ChatRequest, baseURL: String, apiKey: String?,
                           continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation) async throws {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.invalidURL
        }
        guard let key = apiKey, !key.isEmpty else {
            throw LLMError.missingAPIKey
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(KeySanitizer.clean(key), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = encodeRequest(request)
        req.timeoutInterval = 120

        let (bytes, response) = try await URLSession.proxyAware.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("非 HTTP 响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw LLMError.unauthorized("HTTP \(http.statusCode)")
        }
        if http.statusCode == 429 {
            throw LLMError.rateLimited(retryAfter: nil)
        }
        if !(200..<300).contains(http.statusCode) {
            var bodyStr = ""
            for try await line in bytes.lines { bodyStr += line + "\n"; if bodyStr.count > 1024 { break } }
            throw LLMError.serverError(status: http.statusCode, body: bodyStr)
        }

        let parser = SSEParser()
        for try await chunk in bytes {
            if Task.isCancelled { break }
            let payloads = await parser.feed(Data([chunk]))
            for payload in payloads {
                guard let data = payload.data(using: .utf8) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let type = obj["type"] as? String ?? ""

                switch type {
                case "content_block_delta":
                    if let delta = obj["delta"] as? [String: Any] {
                        if let text = delta["text"] as? String {
                            continuation.yield(.textDelta(text))
                        }
                        if let pj = delta["partial_json"] as? String,
                           let idx = obj["index"] as? Int {
                            continuation.yield(.toolCallDelta(id: "block-\(idx)", name: nil, argsDelta: pj))
                        }
                    }
                case "message_stop":
                    continuation.yield(.finished(reason: "stop"))
                    continuation.finish()
                    return
                case "error":
                    let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "unknown"
                    throw LLMError.streamInterrupted(msg)
                default:
                    continue
                }
            }
        }
        continuation.finish()
    }

    private func encodeRequest(_ r: ChatRequest) -> Data {
        // Anthropic: system prompt 放顶层 system，messages 只含 user/assistant
        var systemPrompt: String? = nil
        var msgs: [[String: Any]] = []
        for m in r.messages {
            switch m.role {
            case .system:
                systemPrompt = (systemPrompt.map { $0 + "\n\n" } ?? "") + m.content
            case .user, .assistant:
                if let attachments = m.attachments, attachments.contains(where: { $0.kind == .image }) {
                    var parts: [[String: Any]] = []
                    if !m.content.isEmpty {
                        parts.append(["type": "text", "text": m.content])
                    }
                    for att in attachments where att.kind == .image {
                        if let b64 = att.dataBase64 {
                            parts.append([
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": att.mimeType,
                                    "data": b64
                                ]
                            ])
                        }
                    }
                    msgs.append(["role": m.role.rawValue, "content": parts])
                } else {
                    msgs.append(["role": m.role.rawValue, "content": m.content])
                }
            case .tool:
                // Anthropic tool result 用 user role + tool_result content block
                msgs.append([
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": m.toolCallId ?? "",
                        "content": m.content
                    ]]
                ])
            }
        }
        var body: [String: Any] = [
            "model": r.model,
            "messages": msgs,
            "stream": r.stream,
            "max_tokens": r.maxTokens ?? 4096,
            "temperature": r.temperature
        ]
        if let sys = systemPrompt { body["system"] = sys }
        if let tools = r.tools, !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                let params = (try? JSONSerialization.jsonObject(with: Data(t.parametersJSON.utf8))) ?? [:]
                return ["name": t.name, "description": t.description, "input_schema": params]
            }
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    func validate(baseURL: String, apiKey: String?, model: String) async -> ValidationResult {
        let start = Date()
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            return ValidationResult(ok: false, message: "URL 无效", latencyMs: nil, modelEcho: nil)
        }
        guard let key = apiKey, !key.isEmpty else {
            return ValidationResult(ok: false, message: "缺少 API Key", latencyMs: nil, modelEcho: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(KeySanitizer.clean(key), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 5,
            "stream": false
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.proxyAware.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = resp as? HTTPURLResponse else {
                return ValidationResult(ok: false, message: "响应异常", latencyMs: ms, modelEcho: nil)
            }
            if http.statusCode == 200 {
                let echo = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["model"] as? String }
                return ValidationResult(ok: true, message: "OK", latencyMs: ms, modelEcho: echo)
            }
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            return ValidationResult(ok: false,
                message: "HTTP \(http.statusCode): \(bodyStr.prefix(200))",
                latencyMs: ms, modelEcho: nil)
        } catch {
            return ValidationResult(ok: false, message: error.localizedDescription, latencyMs: nil, modelEcho: nil)
        }
    }
}
