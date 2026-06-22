import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var context
    @AppStorage("dataSendConsentGiven") private var dataSendConsentGiven = false
    @State private var input: String = ""
    @State private var engine = ChatEngine()
    @State private var pendingAttachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showConsentAlert = false
    @State private var consentProviderName = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            if !pendingAttachments.isEmpty { attachmentBar }
            inputBar
        }
        .navigationTitle(conversation.title ?? conversation.agent?.name ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                attachFile(url)
            }
        }
        .sheet(isPresented: $showConsentAlert) {
            PrivacyConsentView(
                providerName: consentProviderName,
                onAgree: {
                    dataSendConsentGiven = true
                    showConsentAlert = false
                    sendMessage()
                },
                onDecline: {
                    showConsentAlert = false
                }
            )
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(conversation.messages.sorted { $0.timestamp < $1.timestamp }) { msg in
                        MessageBubble(message: msg, isStreaming: msg.id == engine.streamingMessageID)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                if let last = conversation.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingAttachments.enumerated()), id: \.offset) { idx, att in
                    AttachmentChip(attachment: att) {
                        pendingAttachments.remove(at: idx)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(.systemGray6))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Menu {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("从相册添加图片", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("添加文件", systemImage: "paperclip")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            VoiceButton { text in
                input = text
            }

            TextField("发消息...", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if engine.isStreaming {
                Button { engine.cancel() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2).foregroundStyle(.red)
                }
            } else {
                Button { send() } label: {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : .gray)
                }
                .disabled(!canSend)
            }
        }
        .padding(8)
        .background(.bar)
    }

    private var canSend: Bool {
        !input.isEmpty || !pendingAttachments.isEmpty
    }

    private func send() {
        guard canSend, let agent = conversation.agent else { return }
        if !dataSendConsentGiven {
            consentProviderName = ProviderRegistry.shared.provider(for: agent.providerKey)?.displayName ?? agent.providerKey
            showConsentAlert = true
            return
        }
        sendMessage()
    }

    private func sendMessage() {
        guard canSend, let agent = conversation.agent else { return }
        let text = input
        let atts = pendingAttachments
        input = ""
        pendingAttachments.removeAll()
        Task {
            await engine.send(userText: text, attachments: atts,
                              in: conversation, agent: agent, context: context)
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { continue }
            let resized = ImageProcessor.resized(img)
            if let (mime, b64) = ImageProcessor.toBase64(resized) {
                pendingAttachments.append(Attachment(
                    kind: .image, mimeType: mime,
                    dataBase64: b64, url: nil, fileName: nil, byteSize: nil
                ))
            }
        }
        photoItems.removeAll()
    }

    private func attachFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = mimeType(for: url.pathExtension)
        pendingAttachments.append(Attachment(
            kind: .file, mimeType: mime,
            dataBase64: data.base64EncodedString(),
            url: nil, fileName: url.lastPathComponent, byteSize: data.count
        ))
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

struct AttachmentChip: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label).lineLimit(1).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.systemBackground))
        .clipShape(Capsule())
    }
    var icon: String {
        switch attachment.kind {
        case .image: return "photo"
        case .file: return "doc"
        case .audio: return "waveform"
        }
    }
    var label: String {
        attachment.fileName ?? attachment.kind.rawValue.capitalized
    }
}

struct VoiceButton: View {
    let onTranscribed: (String) -> Void
    @State private var recorder = VoiceRecorder()
    @State private var showPermissionAlert = false
    @State private var toastMessage: String?
    @State private var toastWorkItem: Task<Void, Never>?

    private let minDuration: TimeInterval = 1.0

    var body: some View {
        ZStack {
            HStack(spacing: 4) {
                Image(systemName: recorder.isRecording
                      ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(recorder.isRecording ? .red : .secondary)
                    .scaleEffect(recorder.isRecording ? 1.25 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                               value: recorder.isRecording)

                if recorder.isRecording {
                    Text(String(format: "%.1fs", recorder.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let msg = toastMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .offset(y: -40)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: toastMessage)
        .onLongPressGesture(minimumDuration: 0.1) {
            // Long press completed — not used; handle via onPressingChanged
        } onPressingChanged: { pressing in
            if pressing {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .alert("麦克风未授权", isPresented: $showPermissionAlert) {
            Button("取消", role: .cancel) {}
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("请在系统设置中允许 Hub-i 访问麦克风，以便使用语音输入功能。")
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.cancel()
            }
            toastWorkItem?.cancel()
        }
    }

    private func startRecording() {
        Task {
            guard await recorder.requestPermission() else {
                await MainActor.run { showPermissionAlert = true }
                return
            }
            do {
                _ = try recorder.start()
            } catch {
                await MainActor.run { showToast("录音启动失败") }
            }
        }
    }

    private func stopRecording() {
        guard recorder.isRecording else { return }
        let dur = recorder.duration

        if dur < minDuration {
            recorder.cancel()
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            showToast("按住说话")
            return
        }

        guard let url = recorder.stop() else {
            showToast("录音停止失败")
            return
        }

        Task {
            do {
                let text = try await SpeechToText.transcribe(url: url)
                await MainActor.run { onTranscribed(text) }
            } catch {
                await MainActor.run { showToast("语音识别失败") }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func showToast(_ msg: String) {
        toastWorkItem?.cancel()
        toastMessage = msg
        let captured = msg
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastMessage == captured {
                toastMessage = nil
            }
        }
        toastWorkItem = task
    }
}

struct MessageBubble: View {
    let message: Message
    let isStreaming: Bool
    @State private var tts = TextToSpeech.shared

    var isUser: Bool { message.role == "user" }
    var attachments: [Attachment] {
        guard let data = message.attachmentMetadata,
              let arr = try? JSONDecoder().decode([Attachment].self, from: data) else { return [] }
        return arr
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, att in
                    AttachmentPreview(attachment: att)
                }
                ForEach(MarkdownRender.segments(message.content), id: \.self) { seg in
                    switch seg {
                    case .text(let t):
                        Text(MarkdownRender.attributed(t))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(isUser ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(isUser ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    case .code(let lang, let content):
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lang.isEmpty ? "code" : lang)
                                    .font(.caption2.bold()).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = content
                                } label: { Image(systemName: "doc.on.doc").font(.caption) }
                            }
                            Text(content)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(10).background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if isStreaming, message.content.isEmpty {
                    ProgressView().padding(8)
                }
                if !isUser, !message.content.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: { Image(systemName: "doc.on.doc") }
                        Button {
                            if tts.isSpeaking { tts.stop() } else { tts.speak(message.content) }
                        } label: {
                            Image(systemName: tts.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct AttachmentPreview: View {
    let attachment: Attachment
    var body: some View {
        switch attachment.kind {
        case .image:
            if let b64 = attachment.dataBase64,
               let data = Data(base64Encoded: b64),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        case .file:
            HStack {
                Image(systemName: "doc.fill").foregroundStyle(.blue)
                Text(attachment.fileName ?? "文件").lineLimit(1)
                if let sz = attachment.byteSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(sz), countStyle: .file))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8).background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .audio:
            HStack { Image(systemName: "waveform"); Text("语音消息") }
        }
    }
}

// MARK: - 隐私同意视图

struct PrivacyConsentView: View {
    let providerName: String
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)

                    Text("隐私声明")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)

                    Text("Hub-i 是一个自带密钥（BYOK）的 AI 客户端。发送消息时：")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ConsentRow(icon: "arrow.up.message.fill", color: .blue, text: "您的消息内容将直接发送给您选择的 AI 服务商")
                        ConsentRow(icon: "building.2.fill", color: .indigo, text: "当前服务商：\(providerName)。其隐私政策适用于您的数据")
                        ConsentRow(icon: "key.fill", color: .orange, text: "您的 API Key 仅存储在设备本地（iOS 钥匙串），不会上传")
                        ConsentRow(icon: "eye.slash.fill", color: .gray, text: "Hub-i 不会收集、存储或分享您的对话内容")
                        ConsentRow(icon: "pencil.line", color: .green, text: "您可以随时在 Agent 设置中修改或删除 API Key")
                    }

                    HStack {
                        Spacer()
                        Link("隐私政策", destination: URL(string: "https://hubi.623101.xyz/privacy")!)
                            .font(.footnote)
                        Spacer()
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("不同意") { onDecline() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAgree()
                } label: {
                    Text("同意并继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

struct ConsentRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
