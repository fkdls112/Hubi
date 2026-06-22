import Foundation
import CFNetwork

// MARK: - 能力声明
enum LLMCapability: String, Sendable, Codable {
    case streaming
    case toolCalling
    case vision
    case audio
    case fileSearch
    case reasoning
}

// MARK: - 角色
enum ChatRole: String, Sendable, Codable {
    case system, user, assistant, tool
}

// MARK: - 消息
struct ChatMessage: Sendable, Codable {
    let role: ChatRole
    let content: String
    var name: String?
    var toolCallId: String?
    var attachments: [Attachment]?

    init(role: ChatRole, content: String, name: String? = nil,
         toolCallId: String? = nil, attachments: [Attachment]? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
        self.attachments = attachments
    }
}

// MARK: - 附件（图片/文件/音频）
struct Attachment: Sendable, Codable {
    enum Kind: String, Sendable, Codable { case image, file, audio }
    let kind: Kind
    let mimeType: String
    let dataBase64: String?      // 内联 base64 (图片优先)
    let url: String?             // 远程 URL
    let fileName: String?
    let byteSize: Int?
}

// MARK: - 请求
struct ChatRequest: Sendable {
    let messages: [ChatMessage]
    let model: String
    var temperature: Double = 0.7
    var maxTokens: Int? = nil
    var tools: [ToolDefinition]? = nil
    var stream: Bool = true
}

// MARK: - 工具定义（OpenAI tool calling 兼容）
struct ToolDefinition: Sendable, Codable {
    let name: String
    let description: String
    let parametersJSON: String   // JSON Schema string
}

// MARK: - 流式事件
enum ChatStreamEvent: Sendable {
    case textDelta(String)                    // 文本增量
    case toolCallDelta(id: String, name: String?, argsDelta: String)
    case finished(reason: String?)            // stop / length / tool_calls
    case error(LLMError)
}

// MARK: - 错误
enum LLMError: Error, Sendable {
    case invalidURL
    case missingAPIKey
    case unauthorized(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, body: String)
    case decodingFailed(String)
    case networkError(String)
    case streamInterrupted(String)
    case validationFailed(String)
}

extension LLMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "服务地址无效"
        case .missingAPIKey:            return "缺少 API Key"
        case .unauthorized(let m):      return "鉴权失败: \(m)"
        case .rateLimited(let r):       return "请求过快\(r.map { ", \($0)秒后重试" } ?? "")"
        case .serverError(let s, let b): return "服务端错误 \(s): \(b.prefix(200))"
        case .decodingFailed(let m):    return "解析失败: \(m)"
        case .networkError(let m):      return "网络错误: \(m)"
        case .streamInterrupted(let m): return "流被中断: \(m)"
        case .validationFailed(let m):  return "校验失败: \(m)"
        }
    }
}

// MARK: - 验证结果
struct ValidationResult: Sendable {
    let ok: Bool
    let message: String
    let latencyMs: Int?
    let modelEcho: String?
}

// MARK: - LLMProvider 协议（每家适配实现这个）
protocol LLMProvider: Sendable {
    var key: String { get }                            // openai / deepseek / hermes / anthropic
    var displayName: String { get }
    var capabilities: Set<LLMCapability> { get }
    var defaultBaseURL: String { get }

    /// 流式聊天
    func stream(request: ChatRequest, baseURL: String, apiKey: String?) -> AsyncThrowingStream<ChatStreamEvent, Error>

    /// 健康检查（连通性 + 鉴权）
    func validate(baseURL: String, apiKey: String?, model: String) async -> ValidationResult
}

// MARK: - 代理感知 URLSession
///
/// macOS 26.x beta 存在 bug：通过「系统设置」配置的 HTTP/HTTPS 代理未正确写入
/// SystemConfiguration 动态存储，导致 CFNetwork / URLSession 看不到代理，直连超时。
/// curl 不受影响是因为它读环境变量 https_proxy。
///
/// 此扩展在模拟器环境下检测 CFNetwork 代理是否为空，若空则回退读取
/// https_proxy / HTTPS_PROXY 环境变量来配置 URLSession。

private func _parseProxyEnv(_ raw: String) -> [String: Any]? {
    var s = raw
    if let range = s.range(of: "://") {
        s = String(s[range.upperBound...])
    }
    let parts = s.components(separatedBy: ":")
    guard let host = parts.first, !host.isEmpty else { return nil }
    let port: Int = parts.count >= 2 ? (Int(parts[1]) ?? 80) : 80
    // 同时设置 HTTP 和 HTTPS 代理（CONNECT 隧道需要 HTTPS proxy host/port）
    return [
        String(kCFProxyTypeKey): kCFProxyTypeHTTP,
        String(kCFProxyHostNameKey): host,
        String(kCFProxyPortNumberKey): port,
        String(kCFStreamPropertyHTTPSProxyHost): host,
        String(kCFStreamPropertyHTTPSProxyPort): port,
    ]
}

extension URLSession {
    /// 一个已配置代理回退的共享 URLSession（模拟器环境下有效）
    static let proxyAware: URLSession = {
        let config = URLSessionConfiguration.default
        let systemProxy = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        let httpOK = (systemProxy["HTTPEnable"] as? Int) == 1
        let httpsOK = (systemProxy["HTTPSEnable"] as? Int) == 1

        #if targetEnvironment(simulator)
        if !httpOK && !httpsOK {
            let envKeys = ["https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY", "all_proxy", "ALL_PROXY"]
            for key in envKeys {
                if let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty,
                   let proxyDict = _parseProxyEnv(raw) {
                    config.connectionProxyDictionary = proxyDict
                    break
                }
            }
        }
        #endif

        return URLSession(configuration: config)
    }()
}
