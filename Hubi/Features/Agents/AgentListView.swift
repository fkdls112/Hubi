import SwiftUI
import SwiftData

struct AgentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText: String = ""
    @State private var entitlement = EntitlementStore.shared
    @State private var showPaywall = false
    @State private var lockedAgentName: String = ""

    var filtered: [Agent] {
        guard !searchText.isEmpty else { return agents }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.systemPrompt ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { agent in
                if isUnlocked(agent) {
                    NavigationLink {
                        AgentEditView(agent: agent)
                    } label: {
                        AgentRow(agent: agent, locked: false)
                    }
                } else {
#if DEBUG
                    Button {
                        lockedAgentName = agent.name
                        showPaywall = true
                    } label: {
                        AgentRow(agent: agent, locked: true)
                    }
                    .buttonStyle(.plain)
#else
                    AgentRow(agent: agent, locked: true)
                        .opacity(0.5)
#endif
                }
            }
            .onDelete(perform: delete)
        }
        .searchable(text: $searchText, prompt: "搜索 Agent")
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createBlank) {
                    Image(systemName: "plus")
                }
            }
        }
#if DEBUG
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                PaywallView()
                    .navigationTitle("解锁 \(lockedAgentName)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { showPaywall = false }
                        }
                    }
            }
        }
#endif
    }

    private func isUnlocked(_ agent: Agent) -> Bool {
        let need = HubiTier.parse(agent.requiredTier)
        return entitlement.currentTier >= need
    }

    private func createBlank() {
        let a = Agent(name: "新 Agent", providerKey: "openai",
                      baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini")
        context.insert(a)
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(filtered[i]) }
        try? context.save()
    }
}

struct AgentRow: View {
    let agent: Agent
    var locked: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: agent.avatarSymbol)
                    .font(.title2)
                    .foregroundStyle(Color(hex: agent.tintColor) ?? .accentColor)
                    .frame(width: 36, height: 36)
                    .background((Color(hex: agent.tintColor) ?? .accentColor).opacity(0.15))
                    .clipShape(Circle())
                    .opacity(locked ? 0.5 : 1.0)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.orange)
                        .clipShape(Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.headline)
                        .foregroundStyle(locked ? .secondary : .primary)
                    if agent.requiredTier != "free" {
                        Text("高级版")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                Text(locked ? "需高级版解锁" : "\(agent.providerKey) · \(agent.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
