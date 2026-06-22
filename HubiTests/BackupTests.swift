import XCTest
import SwiftData
@testable import Hubi

final class BackupTests: XCTestCase {

    @MainActor
    func testExportImportRoundtrip() throws {
        let schema = Schema([Agent.self, Conversation.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)

        let agent = Agent(name: "测试", providerKey: "openai", baseURL: "https://api.openai.com/v1",
                          model: "gpt-4o-mini")
        ctx.insert(agent)
        let conv = Conversation()
        conv.agent = agent
        ctx.insert(conv)
        let msg = Message(role: "user", content: "hello")
        msg.conversation = conv
        ctx.insert(msg)
        try ctx.save()

        let url = try BackupService.shared.exportToFile(context: ctx, password: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // 新容器导入
        let container2 = try ModelContainer(for: schema, configurations: [config])
        let ctx2 = ModelContext(container2)
        let summary = try BackupService.shared.importFromFile(url: url, context: ctx2, password: nil)

        XCTAssertEqual(summary.addedAgents, 1)
        XCTAssertEqual(summary.addedConversations, 1)
        XCTAssertEqual(summary.addedMessages, 1)
    }

    @MainActor
    func testEncryptedRoundtrip() throws {
        let schema = Schema([Agent.self, Conversation.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        ctx.insert(Agent(name: "X", providerKey: "openai", baseURL: "https://api.openai.com/v1",
                          model: "gpt-4o-mini"))
        try ctx.save()

        let url = try BackupService.shared.exportToFile(context: ctx, password: "test1234")
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".hubibackup.enc"))

        let container2 = try ModelContainer(for: schema, configurations: [config])
        let ctx2 = ModelContext(container2)
        let summary = try BackupService.shared.importFromFile(url: url, context: ctx2, password: "test1234")
        XCTAssertEqual(summary.addedAgents, 1)

        // 错误密码
        let ctx3 = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        XCTAssertThrowsError(try BackupService.shared.importFromFile(url: url, context: ctx3, password: "wrong"))
    }
}
