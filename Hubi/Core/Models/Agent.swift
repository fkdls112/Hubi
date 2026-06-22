import Foundation

// SchemaV1 是当前激活的 Schema。后续升级时只改 typealias 指向 SchemaV2。
typealias Agent = SchemaV1.Agent
typealias Conversation = SchemaV1.Conversation
typealias Message = SchemaV1.Message
