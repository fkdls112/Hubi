import Foundation

/// .hubibackup 文件结构（JSON）
struct BackupBundle: Codable {
    let version: Int
    let createdAt: Date
    let appVersion: String
    let agents: [AgentDTO]
    let conversations: [ConversationDTO]

    static let currentVersion = 1

    struct AgentDTO: Codable {
        var id: UUID
        var name: String
        var providerKey: String
        var baseURL: String
        var model: String
        var systemPrompt: String?
        var temperature: Double?
        var maxTokens: Int?
        var avatarSymbol: String
        var tintColor: String
        var requiredTier: String
        var keychainKey: String?  // API Key 不写入备份
    }

    struct ConversationDTO: Codable {
        var id: UUID
        var title: String?
        var agentID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var messages: [MessageDTO]
    }

    struct MessageDTO: Codable {
        var id: UUID
        var role: String
        var content: String
        var timestamp: Date
        var attachments: [AttachmentDTO]?
    }

    struct AttachmentDTO: Codable {
        var kind: String       // image / file / audio
        var fileName: String
        var mimeType: String
        var dataB64: String?   // 小附件直接 base64；大附件单独打包
    }
}
