import Foundation
import SwiftData
import CryptoKit

@MainActor
final class BackupService {
    static let shared = BackupService()
    private init() {}

    enum BackupError: LocalizedError {
        case encodingFailed
        case writeFailed(String)
        case readFailed(String)
        case decodeFailed(String)
        case versionUnsupported(Int)
        case decryptFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:           return "导出编码失败"
            case .writeFailed(let s):       return "写入失败: \(s)"
            case .readFailed(let s):        return "读取失败: \(s)"
            case .decodeFailed(let s):      return "解析失败: \(s)"
            case .versionUnsupported(let v):return "不支持的备份版本 v\(v)"
            case .decryptFailed:            return "解密失败（密码错误？）"
            }
        }
    }

    // MARK: - 导出
    /// 导出整库到 .hubibackup 文件
    /// - Parameter password: 可选；非 nil 则 AES-GCM 加密
    func exportToFile(context: ModelContext, password: String? = nil) throws -> URL {
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let conversations = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []

        let bundle = BackupBundle(
            version: BackupBundle.currentVersion,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            agents: agents.map(toDTO),
            conversations: conversations.map(toDTO)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(bundle)
        } catch {
            throw BackupError.encodingFailed
        }

        let payload: Data = try {
            guard let pwd = password, !pwd.isEmpty else { return data }
            return try encrypt(data, password: pwd)
        }()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        let suffix = password == nil ? "hubibackup" : "hubibackup.enc"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hubi-\(stamp).\(suffix)")
        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
        AppLogger.shared.info("备份导出: \(url.lastPathComponent) size=\(payload.count)")
        return url
    }

    // MARK: - 导入
    func importFromFile(url: URL, context: ModelContext, password: String? = nil) throws -> ImportSummary {
        let raw: Data
        do { raw = try Data(contentsOf: url) }
        catch { throw BackupError.readFailed(error.localizedDescription) }

        let isEncrypted = url.lastPathComponent.hasSuffix(".enc")
        let decrypted: Data = try {
            guard isEncrypted else { return raw }
            guard let pwd = password, !pwd.isEmpty else {
                throw BackupError.decryptFailed
            }
            return try decrypt(raw, password: pwd)
        }()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle: BackupBundle
        do { bundle = try decoder.decode(BackupBundle.self, from: decrypted) }
        catch { throw BackupError.decodeFailed(error.localizedDescription) }

        if bundle.version > BackupBundle.currentVersion {
            throw BackupError.versionUnsupported(bundle.version)
        }

        // 增量合并: 同 ID 跳过, 不存在则插入
        let existingAgentIDs = Set(((try? context.fetch(FetchDescriptor<Agent>())) ?? []).map(\.id))
        let existingConvIDs = Set(((try? context.fetch(FetchDescriptor<Conversation>())) ?? []).map(\.id))

        var addedAgents = 0
        var addedConvs = 0
        var addedMsgs = 0

        for dto in bundle.agents where !existingAgentIDs.contains(dto.id) {
            context.insert(fromDTO(dto))
            addedAgents += 1
        }

        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentByID = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })

        for cdto in bundle.conversations where !existingConvIDs.contains(cdto.id) {
            let conv = Conversation()
            conv.id = cdto.id
            conv.title = cdto.title
            conv.createdAt = cdto.createdAt
            conv.updatedAt = cdto.updatedAt
            if let aid = cdto.agentID, let agent = agentByID[aid] {
                conv.agent = agent
            }
            context.insert(conv)
            for mdto in cdto.messages {
                let msg = Message(role: mdto.role, content: mdto.content)
                msg.id = mdto.id
                msg.timestamp = mdto.timestamp
                msg.conversation = conv
                context.insert(msg)
                addedMsgs += 1
            }
            addedConvs += 1
        }

        try? context.save()
        AppLogger.shared.info("导入完成 agents+\(addedAgents) conv+\(addedConvs) msg+\(addedMsgs)")

        return ImportSummary(
            addedAgents: addedAgents,
            addedConversations: addedConvs,
            addedMessages: addedMsgs,
            sourceVersion: bundle.version,
            sourceCreatedAt: bundle.createdAt
        )
    }

    struct ImportSummary {
        let addedAgents: Int
        let addedConversations: Int
        let addedMessages: Int
        let sourceVersion: Int
        let sourceCreatedAt: Date
    }

    // MARK: - DTO
    private func toDTO(_ a: Agent) -> BackupBundle.AgentDTO {
        BackupBundle.AgentDTO(
            id: a.id, name: a.name, providerKey: a.providerKey, baseURL: a.baseURL,
            model: a.model, systemPrompt: a.systemPrompt, temperature: a.temperature,
            maxTokens: a.maxTokens, avatarSymbol: a.avatarSymbol, tintColor: a.tintColor,
            requiredTier: a.requiredTier, keychainKey: nil
        )
    }
    private func fromDTO(_ d: BackupBundle.AgentDTO) -> Agent {
        let a = Agent(
            name: d.name, providerKey: d.providerKey,
            baseURL: d.baseURL, model: d.model
        )
        a.id = d.id
        a.systemPrompt = d.systemPrompt
        if let t = d.temperature { a.temperature = t }
        a.maxTokens = d.maxTokens
        a.avatarSymbol = d.avatarSymbol
        a.tintColor = d.tintColor
        a.requiredTier = d.requiredTier
        return a
    }
    private func toDTO(_ c: Conversation) -> BackupBundle.ConversationDTO {
        BackupBundle.ConversationDTO(
            id: c.id, title: c.title, agentID: c.agent?.id,
            createdAt: c.createdAt, updatedAt: c.updatedAt,
            messages: c.messages.sorted(by: { $0.timestamp < $1.timestamp }).map {
                BackupBundle.MessageDTO(
                    id: $0.id, role: $0.role, content: $0.content,
                    timestamp: $0.timestamp, attachments: nil
                )
            }
        )
    }

    // MARK: - 加密 (AES-GCM, scrypt-like KDF using SHA256 over salt+pwd 100k 次)
    private func encrypt(_ data: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let key = deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        // 文件格式: "HUBE" + salt(16) + nonce(12) + ciphertext + tag(16)
        var out = Data("HUBE".utf8)
        out.append(salt)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }
    private func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count > 4 + 16 + 12 + 16,
              data.prefix(4) == Data("HUBE".utf8) else {
            throw BackupError.decryptFailed
        }
        let salt = data.subdata(in: 4..<20)
        let nonceData = data.subdata(in: 20..<32)
        let tag = data.suffix(16)
        let cipher = data.subdata(in: 32..<(data.count - 16))
        let key = deriveKey(password: password, salt: salt)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag)
            return try AES.GCM.open(box, using: key)
        } catch { throw BackupError.decryptFailed }
    }
    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        var data = salt + Data(password.utf8)
        for _ in 0..<10_000 {
            data = Data(SHA256.hash(data: data))
        }
        return SymmetricKey(data: data)
    }
}
