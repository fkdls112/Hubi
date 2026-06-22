import Foundation

/// OpenAI 兼容协议 Provider
/// 适配: OpenAI 官方 / DeepSeek / Hermes API Server / 任何 OpenAI 兼容端点
struct OpenAIProvider: LLMProvider {
    let key: String
    let displayName: String
    var capabilities: Set<LLMCapability> = [.streaming, .toolCalling, .vision]
    let defaultBaseURL: String

    static let openAI = OpenAIProvider(
        key: "openai", displayName: "OpenAI",
        defaultBaseURL: "https://api.openai.com/v1"
    )
    static let deepseek = OpenAIProvider(
        key: "deepseek", displayName: "DeepSeek",
        capabilities: [.streaming, .toolCalling, .reasoning],
        defaultBaseURL: "https://api.deepseek.com/v1"
    )
    static let hermes = OpenAIProvider(
        key: "hermes", displayName: "Hermes",
        capabilities: [.streaming, .toolCalling, .vision, .fileSearch],
        defaultBaseURL: "http://192.168.2.108:8642/v1"
    )

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
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(KeySanitizer.clean(key))", forHTTPHeaderField: "Authorization")
        }

        let body = encodeRequest(request)
        req.httpBody = body
        req.timeoutInterval = 120

        let (bytes, response) = try await URLSession.proxyAware.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("非 HTTP 响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw LLMError.unauthorized("HTTP \(http.statusCode)")
        }
        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw LLMError.rateLimited(retryAfter: retry)
        }
        if !(200..<300).contains(http.statusCode) {
            var bodyStr = ""
            for try await line in bytes.lines { bodyStr += line + "\n"; if bodyStr.count > 1024 { break } }
            throw LLMError.serverError(status: http.statusCode, body: bodyStr)
        }

        let parser = SSEParser()
        var partialToolArgs: [String: String] = [:]

        for try await chunk in bytes {
            if Task.isCancelled { break }
            let payloads = await parser.feed(Data([chunk]))
            for payload in payloads {
                if payload == "[DONE]" {
                    continuation.yield(.finished(reason: "stop"))
                    continuation.finish()
                    return
                }
                guard let data = payload.data(using: .utf8) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                guard let choices = obj["choices"] as? [[String: Any]],
                      let first = choices.first else { continue }

                if let delta = first["delta"] as? [String: Any] {
                    if let content = delta["content"] as? String, !content.isEmpty {
                        continuation.yield(.textDelta(content))
                    }
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        for call in toolCalls {
                            let id = call["id"] as? String ?? ""
                            if let fn = call["function"] as? [String: Any] {
                                let name = fn["name"] as? String
                                let args = fn["arguments"] as? String ?? ""
                                partialToolArgs[id, default: ""] += args
                                continuation.yield(.toolCallDelta(id: id, name: name, argsDelta: args))
                            }
                        }
                    }
                }
                if let reason = first["finish_reason"] as? String {
                    continuation.yield(.finished(reason: reason))
                    continuation.finish()
                    return
                }
            }
        }
        continuation.finish()
    }

    private func encodeRequest(_ r: ChatRequest) -> Data {
        var msgs: [[String: Any]] = []
        for m in r.messages {
            var msg: [String: Any] = ["role": m.role.rawValue]
            if let attachments = m.attachments, !attachments.isEmpty {
                // 多模态格式: content = [{type:"text",text:...},{type:"image_url",image_url:{url:...}}]
                var parts: [[String: Any]] = []
                if !m.content.isEmpty {
                    parts.append(["type": "text", "text": m.content])
                }
                for att in attachments where att.kind == .image {
                    if let b64 = att.dataBase64 {
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(att.mimeType);base64,\(b64)"]
                        ])
                    } else if let url = att.url {
                        parts.append(["type": "image_url", "image_url": ["url": url]])
                    }
                }
                msg["content"] = parts
            } else {
                msg["content"] = m.content
            }
            if let n = m.name { msg["name"] = n }
            if let t = m.toolCallId { msg["tool_call_id"] = t }
            msgs.append(msg)
        }
        var body: [String: Any] = [
            "model": r.model,
            "messages": msgs,
            "stream": r.stream,
            "temperature": r.temperature
        ]
        if let mt = r.maxTokens { body["max_tokens"] = mt }
        if let tools = r.tools, !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                let params = (try? JSONSerialization.jsonObject(with: Data(t.parametersJSON.utf8))) ?? [:]
                return ["type": "function", "function": [
                    "name": t.name, "description": t.description, "parameters": params
                ]]
            }
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    func validate(baseURL: String, apiKey: String?, model: String) async -> ValidationResult {
        let start = Date()
        let request = ChatRequest(
            messages: [ChatMessage(role: .user, content: "ping")],
            model: model, temperature: 0, maxTokens: 5, tools: nil, stream: false
        )

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return ValidationResult(ok: false, message: "URL 无效", latencyMs: nil, modelEcho: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(KeySanitizer.clean(key))", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = encodeRequest(request)
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.proxyAware.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = resp as? HTTPURLResponse else {
                return ValidationResult(ok: false, message: "响应异常", latencyMs: ms, modelEcho: nil)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 200 {
                let echo = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["model"] as? String }
                return ValidationResult(ok: true, message: "OK", latencyMs: ms, modelEcho: echo)
            }
            return ValidationResult(ok: false,
                message: "HTTP \(http.statusCode): \(body.prefix(200))",
                latencyMs: ms, modelEcho: nil)
        } catch {
            return ValidationResult(ok: false, message: error.localizedDescription, latencyMs: nil, modelEcho: nil)
        }
    }
}
