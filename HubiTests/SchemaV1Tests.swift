import XCTest
import SwiftData
@testable import Hubi

final class SchemaV1Tests: XCTestCase {

    func testAgentCreation() throws {
        let container = try ModelContainer.hubiInMemory()
        let context = ModelContext(container)

        let agent = Agent(
            name: "Test",
            providerKey: "openai",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o"
        )
        context.insert(agent)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Agent>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test")
        XCTAssertEqual(fetched.first?.temperature, 0.7)
    }

    func testKeychainReadWrite() {
        let key = "hubi.test.\(UUID())"
        KeychainStore.shared.write(key: key, value: "secret-value")
        XCTAssertEqual(KeychainStore.shared.read(key: key), "secret-value")

        KeychainStore.shared.write(key: key, value: nil)
        XCTAssertNil(KeychainStore.shared.read(key: key))
    }

    func testKeySanitizer() {
        let dirty = "  sk-abc\u{200B}def\u{00A0}123\n"
        let clean = KeySanitizer.clean(dirty)
        XCTAssertEqual(clean, "sk-abcdef123")
    }

    func testHealthCheckCleansOrphans() async throws {
        let container = try ModelContainer.hubiInMemory()
        let context = ModelContext(container)

        // 创建一个 Agent
        let agent = Agent(name: "Live", providerKey: "openai",
                          baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        context.insert(agent)
        try context.save()

        // 写入对应 Keychain
        let liveKey = "hubi.agent.\(agent.id)"
        KeychainStore.shared.write(key: liveKey, value: "live-key")

        // 写入孤儿 Keychain（对应一个不存在的 Agent ID）
        let orphanKey = "hubi.agent.\(UUID())"
        KeychainStore.shared.write(key: orphanKey, value: "orphan-key")

        XCTAssertNotNil(KeychainStore.shared.read(key: orphanKey))

        await HealthCheck.run(container: container)

        // 孤儿应被清理，存活的应保留
        XCTAssertNil(KeychainStore.shared.read(key: orphanKey))
        XCTAssertEqual(KeychainStore.shared.read(key: liveKey), "live-key")

        // 清理
        KeychainStore.shared.write(key: liveKey, value: nil)
    }
}
