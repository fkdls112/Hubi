import Foundation
import SwiftData
import Observation

/// ChatEngine 负责协调：组装请求 -> 调 Provider 流 -> 增量写回 SwiftData
@MainActor
@Observable
final class ChatEngine {
    private(set) var streamingMessageID: UUID?
    private(set) var isStreaming: Bool = false
    private var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
        streamingMessageID = nil
    }

    /// 发送一条用户消息并启动流式回复
    func send(
        userText: String,
        attachments: [Attachment] = [],
        in conversation: Conversation,
        agent: Agent,
        context: ModelContext
    ) async {
        cancel()

        // 1. 写入 user message
        let userMsg = Message(role: ChatRole.user.rawValue, content: userText)
        if !attachments.isEmpty,
           let data = try? JSONEncoder().encode(attachments) {
            userMsg.attachmentMetadata = data
        }
        userMsg.conversation = conversation
        context.insert(userMsg)
        conversation.messages.append(userMsg)

        // 2. 占位 assistant message
        let assistantMsg = Message(role: ChatRole.assistant.rawValue, content: "")
        assistantMsg.status = "streaming"
        assistantMsg.conversation = conversation
        context.insert(assistantMsg)
        conversation.messages.append(assistantMsg)
        conversation.updatedAt = Date()
        try? context.save()

        streamingMessageID = assistantMsg.id
        isStreaming = true

        // 3. 组装历史
        let history = buildHistory(conversation: conversation, agent: agent)

        // 4. Provider 选择
        guard let provider = ProviderRegistry.shared.provider(for: agent.providerKey) else {
            assistantMsg.status = "error"
            assistantMsg.content = "未找到 Provider: \(agent.providerKey)"
            isStreaming = false
            try? context.save()
            return
        }
        let apiKey = agent.apiKey
        let baseURL = agent.baseURL.isEmpty ? provider.defaultBaseURL : agent.baseURL

        let req = ChatRequest(
            messages: history,
            model: agent.model,
            temperature: agent.temperature,
            maxTokens: agent.maxTokens,
            stream: true
        )

        // 5. 启动流
        currentTask = Task { [weak self, assistantMsg] in
            guard let self else { return }
            var accumulated = ""
            var finishReason: String?
            do {
                for try await event in provider.stream(request: req, baseURL: baseURL, apiKey: apiKey) {
                    if Task.isCancelled { break }
                    switch event {
                    case .textDelta(let t):
                        accumulated += t
                        await MainActor.run {
                            assistantMsg.content = accumulated
                        }
                    case .toolCallDelta:
                        continue  // W4 处理工具调用
                    case .finished(let r):
                        finishReason = r
                    case .error(let e):
                        throw e
                    }
                }
                await MainActor.run {
                    assistantMsg.content = accumulated
                    assistantMsg.status = "sent"
                    if conversation.title == nil, !accumulated.isEmpty {
                        conversation.title = String(userText.prefix(20))
                    }
                    try? context.save()
                    self.isStreaming = false
                    self.streamingMessageID = nil
                    AppLogger.shared.info("Chat finished, reason=\(finishReason ?? "?")")
                }
            } catch {
                await MainActor.run {
                    if accumulated.isEmpty {
                        assistantMsg.content = "❌ \(error.localizedDescription)"
                    } else {
                        assistantMsg.content = accumulated + "\n\n_(中断: \(error.localizedDescription))_"
                    }
                    assistantMsg.status = "error"
                    try? context.save()
                    self.isStreaming = false
                    self.streamingMessageID = nil
                    AppLogger.shared.error("Chat stream error: \(error)")
                }
            }
        }
    }

    private func buildHistory(conversation: Conversation, agent: Agent) -> [ChatMessage] {
        var msgs: [ChatMessage] = []
        if let sp = agent.systemPrompt, !sp.isEmpty {
            msgs.append(ChatMessage(role: .system, content: sp))
        }
        let sorted = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        // 不包含正在流式的占位消息（最后一条 streaming 状态）
        for m in sorted where m.status != "streaming" {
            guard let role = ChatRole(rawValue: m.role) else { continue }
            var attachments: [Attachment]?
            if let data = m.attachmentMetadata {
                attachments = try? JSONDecoder().decode([Attachment].self, from: data)
            }
            msgs.append(ChatMessage(role: role, content: m.content, attachments: attachments))
        }
        return msgs
    }
}
