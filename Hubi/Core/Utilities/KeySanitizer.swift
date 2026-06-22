import Foundation

/// 清洗 API Key：去掉非 ASCII / 控制字符 / 首尾空白。
/// 修复 Flutter 版踩过的坑：用户复制 Key 时带入零宽空格 / NBSP，HTTP Header 拒收。
enum KeySanitizer {
    static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.unicodeScalars
            .filter { $0.isASCII && !$0.properties.isWhitespace && !($0.value < 0x20) }
            .reduce(into: "") { $0.append(Character($1)) }
    }
}
