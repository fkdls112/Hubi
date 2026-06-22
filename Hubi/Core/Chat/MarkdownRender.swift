import Foundation
import SwiftUI

/// 用系统 AttributedString(markdown:) 实现轻量 Markdown 渲染
/// 支持: 加粗/斜体/链接/inline code/代码块（fallback）/列表
enum MarkdownRender {
    static func attributed(_ text: String) -> AttributedString {
        // 系统解析器：会处理 **bold** *italic* `code` [link](url)
        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(text)
        }
    }

    /// 把消息内容拆成 [文本片段, 代码块片段] 序列，供 UI 区分渲染
    static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0
        var buffer: [String] = []
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                if !buffer.isEmpty {
                    out.append(.text(buffer.joined(separator: "\n")))
                    buffer.removeAll()
                }
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                out.append(.code(language: lang, content: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            buffer.append(line)
            i += 1
        }
        if !buffer.isEmpty {
            out.append(.text(buffer.joined(separator: "\n")))
        }
        return out
    }

    enum Segment: Hashable {
        case text(String)
        case code(language: String, content: String)
    }
}
