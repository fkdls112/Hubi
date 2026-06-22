import Foundation

/// SSE (Server-Sent Events) 行解析器
/// 输入字节流，输出 data: 后面的 payload；处理 \r\n / \n / 跨 chunk 半行
actor SSEParser {
    private var buffer = Data()

    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var payloads: [String] = []

        while let range = buffer.range(of: Data([0x0A])) {  // \n
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)

            // strip trailing \r
            var bytes = lineData
            if bytes.last == 0x0D { bytes.removeLast() }
            guard let line = String(data: bytes, encoding: .utf8) else { continue }

            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                payloads.append(payload)
            }
            // 忽略 event:/id:/retry:/空行/comment(:)
        }
        return payloads
    }

    func reset() { buffer.removeAll() }
}
