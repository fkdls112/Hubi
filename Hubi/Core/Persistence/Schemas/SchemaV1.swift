import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Agent.self, Conversation.self, Message.self]
    }
}

extension SchemaV1 {
    @Model final class Agent {
        @Attribute(.unique) var id: UUID
        var name: String
        var providerKey: String
        var baseURL: String
        var model: String
        var systemPrompt: String?
        var temperature: Double = 0.7
        var maxTokens: Int? = nil
        var avatarSymbol: String = "sparkle"
        var tintColor: String = "#FF9500"
        var capabilities: [String] = []
        var requiredTier: String = "free"
        var createdAt: Date = Date.now
        var lastActiveAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \Conversation.agent)
        var conversations: [Conversation] = []

        var apiKey: String? {
            get { KeychainStore.shared.read(key: "hubi.agent.\(id)") }
            set { KeychainStore.shared.write(key: "hubi.agent.\(id)", value: newValue) }
        }

        init(name: String, providerKey: String, baseURL: String, model: String) {
            self.id = UUID()
            self.name = name
            self.providerKey = providerKey
            self.baseURL = baseURL
            self.model = model
        }
    }

    @Model final class Conversation {
        @Attribute(.unique) var id: UUID
        var title: String?
        var isPinned: Bool = false
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now

        var agent: Agent?

        @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
        var messages: [Message] = []

        init() { self.id = UUID() }
    }

    @Model final class Message {
        @Attribute(.unique) var id: UUID
        var role: String
        var content: String
        var status: String = "sent"
        var timestamp: Date = Date.now

        var attachmentMetadata: Data?
        var voiceDuration: Double?
        var voiceTranscript: String?
        var voiceWaveform: Data?
        var toolCallsJSON: String?

        var conversation: Conversation?

        init(role: String, content: String) {
            self.id = UUID()
            self.role = role
            self.content = content
        }
    }
}
