import XCTest
@testable import Hubi

final class ProviderTests: XCTestCase {

    func testSSEParserSimple() async {
        let parser = SSEParser()
        let input = "data: hello\ndata: world\n\n".data(using: .utf8)!
        let out = await parser.feed(input)
        XCTAssertEqual(out, ["hello", "world"])
    }

    func testSSEParserCrLfAndPartial() async {
        let parser = SSEParser()
        let chunk1 = "data: ".data(using: .utf8)!
        let chunk2 = "split\r\ndata: full\r\n".data(using: .utf8)!
        let r1 = await parser.feed(chunk1)
        let r2 = await parser.feed(chunk2)
        XCTAssertTrue(r1.isEmpty)
        XCTAssertEqual(r2, ["split", "full"])
    }

    func testSSEParserDONE() async {
        let parser = SSEParser()
        let input = "data: [DONE]\n".data(using: .utf8)!
        let out = await parser.feed(input)
        XCTAssertEqual(out, ["[DONE]"])
    }

    @MainActor
    func testProviderRegistryHasFour() {
        let r = ProviderRegistry.shared
        XCTAssertNotNil(r.provider(for: "openai"))
        XCTAssertNotNil(r.provider(for: "deepseek"))
        XCTAssertNotNil(r.provider(for: "hermes"))
        XCTAssertNotNil(r.provider(for: "anthropic"))
    }

    func testChatRequestStructure() {
        let req = ChatRequest(
            messages: [
                ChatMessage(role: .system, content: "you are helpful"),
                ChatMessage(role: .user, content: "hi")
            ],
            model: "gpt-4o",
            temperature: 0.5,
            maxTokens: 100
        )
        XCTAssertEqual(req.messages.count, 2)
        XCTAssertEqual(req.temperature, 0.5)
        XCTAssertEqual(req.maxTokens, 100)
        XCTAssertTrue(req.stream)
    }

    func testKeySanitizerInProviderFlow() {
        let dirty = "  sk-test\u{200B}key\n"
        XCTAssertEqual(KeySanitizer.clean(dirty), "sk-testkey")
    }

    func testLLMErrorLocalized() {
        XCTAssertEqual(LLMError.invalidURL.errorDescription, "服务地址无效")
        XCTAssertEqual(LLMError.missingAPIKey.errorDescription, "缺少 API Key")
    }

    func testAnthropicProviderBasics() {
        let p = AnthropicProvider()
        XCTAssertEqual(p.key, "anthropic")
        XCTAssertTrue(p.capabilities.contains(.streaming))
        XCTAssertTrue(p.capabilities.contains(.vision))
    }

    func testOpenAIProviderBasics() {
        let p = OpenAIProvider.openAI
        XCTAssertEqual(p.key, "openai")
        XCTAssertEqual(p.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertTrue(p.capabilities.contains(.streaming))
    }
}
