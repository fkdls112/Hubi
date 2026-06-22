import SwiftUI
import SwiftData

struct AgentEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var agent: Agent

    @State private var apiKeyInput: String = ""
    @State private var validating: Bool = false
    @State private var validationResult: String?
    @State private var validationOK: Bool = false
    @State private var entitlement = EntitlementStore.shared
    @State private var showPaywall = false

    // 模型选择
    @State private var selectedModel: String = ""
    @State private var customModel: String = ""
    @State private var isCustomModel: Bool = false
    @State private var fetchedModels: [String] = []
    @State private var fetchingModels: Bool = false
    @State private var fetchModelsTask: Task<Void, Never>?

    private var templates: [ProviderTemplate] {
        ProviderRegistry.shared.templates
    }

    /// 当前选中的模板 id（基于 baseURL+model 反查；为空表示自定义）
    private var currentTemplateID: String {
        templates.first(where: {
            $0.providerKey == agent.providerKey
                && ($0.defaultBaseURL == agent.baseURL || (!$0.defaultBaseURL.isEmpty && agent.baseURL.isEmpty))
        })?.id ?? ""
    }

    /// 预设常用模型（按协议分类）
    private var presetModels: [String] {
        switch agent.providerKey {
        case "deepseek": return ["deepseek-chat", "deepseek-reasoner"]
        case "openai":   return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo", "o1", "o1-mini"]
        case "anthropic":return ["claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5"]
        case "hermes":   return ["hermes-agent", "hermes-3"]
        default:         return []
        }
    }

    /// 所有可选模型 = 预设 + 远程拉取
    private var availableModels: [String] {
        var models = presetModels
        for m in fetchedModels where !models.contains(m) { models.append(m) }
        return models
    }

    var body: some View {
        Form {
            Section("基础") {
                TextField("名称", text: $agent.name)

                Picker("API 来源", selection: Binding(
                    get: { currentTemplateID },
                    set: { newID in applyTemplate(id: newID) }
                )) {
                    Text("自定义").tag("")
                    ForEach(templates) { t in
                        HStack {
                            Image(systemName: t.icon)
                                .foregroundStyle(Color(hex: t.tintColor) ?? .secondary)
                            Text(t.name)
                            if HubiTier.parse(t.requiredTier) != .free {
                                Text("高级版")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.tint.opacity(0.2)))
                            }
                        }
                        .tag(t.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("接口协议", selection: $agent.providerKey) {
                    ForEach(ProviderRegistry.shared.providers.sorted(by: { $0.key < $1.key }), id: \.key) { key, provider in
                        Text(provider.displayName).tag(key)
                    }
                }
                .pickerStyle(.menu)

                TextField("Base URL", text: $agent.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: agent.baseURL) { _, _ in scheduleFetchModels() }

                Picker("模型", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                    Divider()
                    Text("自定义...").tag("__custom__")
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModel) { _, new in
                    if new == "__custom__" {
                        isCustomModel = true
                        agent.model = customModel
                    } else {
                        isCustomModel = false
                        customModel = new
                        agent.model = new
                    }
                }
                .onAppear {
                    syncModelSelection()
                }
                .onChange(of: agent.providerKey) { _, _ in
                    syncModelSelection()
                }

                if isCustomModel {
                    TextField("输入模型名称", text: $customModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: customModel) { _, new in
                            agent.model = new
                        }
                }
            }

            Section("API Key / Token") {
                SecureField("sk-... 或 Bearer Token", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onAppear { apiKeyInput = agent.apiKey ?? "" }
                    .onChange(of: apiKeyInput) { _, new in
                        agent.apiKey = new.isEmpty ? nil : new
                        scheduleFetchModels()
                    }
                Button {
                    validate()
                } label: {
                    HStack {
                        if validating { ProgressView() }
                        Text("测试连通性")
                    }
                }
                if let result = validationResult {
                    Label(result, systemImage: validationOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(validationOK ? .green : .red)
                        .font(.footnote)
                }
            }

            Section("System Prompt") {
                TextEditor(text: Binding(
                    get: { agent.systemPrompt ?? "" },
                    set: { agent.systemPrompt = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }

            Section("生成参数") {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", agent.temperature))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $agent.temperature, in: 0...2, step: 0.1)
                Stepper(value: Binding(
                    get: { agent.maxTokens ?? 0 },
                    set: { agent.maxTokens = $0 == 0 ? nil : $0 }
                ), in: 0...32000, step: 256) {
                    Text("Max Tokens: \(agent.maxTokens.map(String.init) ?? "默认")")
                }
            }
        }
        .navigationTitle(agent.name.isEmpty ? "新建 Agent" : agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    try? context.save()
                    dismiss()
                }
            }
        }
#if DEBUG
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
#endif
    }

    private func applyTemplate(id: String) {
        guard !id.isEmpty, let t = templates.first(where: { $0.id == id }) else {
            // 选择"自定义"：默认 OpenAI 兼容，免费可用
            agent.providerKey = "openai"
            agent.requiredTier = "free"
            return
        }
        // 预设模板属高级版；免费用户拦截并引导订阅
        if HubiTier.parse(t.requiredTier) != .free && entitlement.currentTier < .premium {
#if DEBUG
            showPaywall = true
#endif
            return
        }
        agent.providerKey = t.providerKey
        agent.baseURL = t.defaultBaseURL
        agent.model = t.defaultModel
        agent.requiredTier = t.requiredTier
    }

    private func syncModelSelection() {
        let model = agent.model
        if model.isEmpty || availableModels.contains(model) {
            selectedModel = model.isEmpty ? availableModels.first ?? "" : model
            isCustomModel = false
            if !model.isEmpty { customModel = model }
        } else {
            isCustomModel = true
            customModel = model
            selectedModel = "__custom__"
        }
    }

    private func scheduleFetchModels() {
        fetchModelsTask?.cancel()
        let baseURL = agent.baseURL
        let apiKey = apiKeyInput
        guard !baseURL.isEmpty else { return }
        fetchModelsTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms debounce
            guard !Task.isCancelled else { return }
            await fetchRemoteModels(baseURL: baseURL, apiKey: apiKey)
        }
    }

    private func fetchRemoteModels(baseURL: String, apiKey: String) async {
        fetchingModels = true
        defer { fetchingModels = false }
        guard let url = URL(string: "\\(baseURL)/models") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if !apiKey.isEmpty {
            req.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.proxyAware.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataList = json["data"] as? [[String: Any]] {
                let models = dataList.compactMap { $0["id"] as? String }
                await MainActor.run {
                    fetchedModels = models
                    syncModelSelection()
                }
            }
        } catch {
            // 静默忽略
        }
    }

    private func validate() {
        validating = true
        validationResult = nil
        Task {
            guard let provider = ProviderRegistry.shared.provider(for: agent.providerKey) else {
                validationResult = "未选择 API 来源"
                validating = false
                return
            }
            let baseURL = agent.baseURL.isEmpty ? provider.defaultBaseURL : agent.baseURL
            let result = await provider.validate(baseURL: baseURL, apiKey: apiKeyInput, model: agent.model)
            validationOK = result.ok
            if result.ok {
                validationResult = "OK · \(result.latencyMs ?? 0)ms · model=\(result.modelEcho ?? "?")"
            } else {
                validationResult = result.message
            }
            validating = false
        }
    }
}


