import SwiftUI
import SwiftData

struct ConversationSearchView: View {
    @Environment(\.modelContext) private var context
    @State private var searchText: String = ""
    @State private var results: [SearchResult] = []

    struct SearchResult: Identifiable {
        let id = UUID()
        let conversation: Conversation
        let message: Message
        let snippet: String
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section { Text("输入关键词全文搜索消息").foregroundStyle(.secondary) }
            } else if results.isEmpty {
                Section { Text("未找到匹配").foregroundStyle(.secondary) }
            } else {
                ForEach(results) { r in
                    NavigationLink {
                        ChatView(conversation: r.conversation)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.conversation.title ?? "对话").font(.headline)
                            Text(r.snippet).font(.caption).lineLimit(2)
                            Text(r.message.timestamp, style: .date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索消息内容")
        .onChange(of: searchText) { _, new in
            performSearch(query: new)
        }
        .navigationTitle("搜索")
    }

    private func performSearch(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        let pred = #Predicate<Message> { msg in
            msg.content.contains(q)
        }
        let descriptor = FetchDescriptor<Message>(
            predicate: pred,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let msgs = try? context.fetch(descriptor) else { return }
        results = msgs.prefix(50).compactMap { msg in
            guard let conv = msg.conversation else { return nil }
            let s = msg.content
            let lower = s.lowercased(), needle = q.lowercased()
            var snippet = String(s.prefix(120))
            if let r = lower.range(of: needle) {
                let start = lower.index(r.lowerBound, offsetBy: -30, limitedBy: lower.startIndex) ?? lower.startIndex
                let end = lower.index(r.upperBound, offsetBy: 60, limitedBy: lower.endIndex) ?? lower.endIndex
                snippet = "..." + String(s[start..<end]) + "..."
            }
            return SearchResult(conversation: conv, message: msg, snippet: snippet)
        }
    }
}
