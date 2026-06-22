import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            ConversationsTab()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
            AgentsTab()
                .tabItem { Label("Agents", systemImage: "person.3") }
            SearchTab()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            SettingsTab()
                .tabItem { Label("设置", systemImage: "gear") }
        }
    }
}

struct ConversationsTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]
    @State private var showAgentPicker = false

    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "暂无对话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("点击 + 选择 Agent 开始")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(conversations) { conv in
                        NavigationLink {
                            ChatView(conversation: conv)
                        } label: {
                            ConversationRow(conversation: conv)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Hub-i")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AgentManager.seedIfEmpty(context: context)
                        showAgentPicker = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .onAppear {
                AgentManager.seedIfEmpty(context: context)
            }
            .sheet(isPresented: $showAgentPicker) {
                AgentPickerSheet { agent in
                    let conv = Conversation()
                    conv.agent = agent
                    context.insert(conv)
                    try? context.save()
                    showAgentPicker = false
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(conversations[i]) }
        try? context.save()
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let agent = conversation.agent {
                    Image(systemName: agent.avatarSymbol)
                        .foregroundStyle(Color(hex: agent.tintColor) ?? .accentColor)
                }
                Text(conversation.title ?? conversation.agent?.name ?? "新对话")
                    .font(.headline)
            }
            if let last = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
                Text(last.content).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Text(conversation.updatedAt, style: .relative)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct AgentPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Agent.name) var agents: [Agent]
    @State private var entitlement = EntitlementStore.shared
    @State private var showPaywall = false
    @State private var lockedName: String = ""
    let onPick: (Agent) -> Void

    var body: some View {
        NavigationStack {
            List(agents) { agent in
                Button {
                    if isUnlocked(agent) {
                        onPick(agent)
                } else {
#if DEBUG
                    lockedName = agent.name
                    showPaywall = true
#else
                    // Release: locked agents non-interactive
                    return
#endif
                }
                } label: {
                    AgentRow(agent: agent, locked: !isUnlocked(agent))
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择 Agent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
#if DEBUG
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PaywallView()
                        .navigationTitle("解锁 \(lockedName)")
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
    }

    private func isUnlocked(_ agent: Agent) -> Bool {
        let need = HubiTier.parse(agent.requiredTier)
        return entitlement.currentTier >= need
    }
}

struct AgentsTab: View {
    var body: some View { NavigationStack { AgentListView() } }
}

struct SearchTab: View {
    var body: some View { NavigationStack { ConversationSearchView() } }
}

struct SettingsTab: View {
    @State private var entitlement = EntitlementStore.shared
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text("会员").font(.headline).foregroundStyle(.primary)
                                Text("当前: \(entitlement.currentTier.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary).font(.caption)
                        }
                    }
                }
                Section {
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("备份与导入", systemImage: "externaldrive")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("诊断", systemImage: "stethoscope")
                    }
                }
                Section {
                    LabeledContent("版本",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Build",
                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                }
                Section {
                    Text("Hub-i V3 · SwiftUI 原生").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}
