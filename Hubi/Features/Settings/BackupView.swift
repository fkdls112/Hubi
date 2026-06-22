import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var password: String = ""
    @State private var encrypt: Bool = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var importingURL: URL?
    @State private var importPassword: String = ""
    @State private var statusMessage: String?
    @State private var statusOK: Bool = false
    @State private var importSummary: BackupService.ImportSummary?
    @State private var working = false

    var body: some View {
        Form {
            Section("导出") {
                Toggle("加密备份", isOn: $encrypt)
                if encrypt {
                    SecureField("设置密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button {
                    Task { await doExport() }
                } label: {
                    HStack {
                        if working { ProgressView() }
                        Image(systemName: "square.and.arrow.up")
                        Text("导出 .hubibackup")
                    }
                }
                .disabled(working || (encrypt && password.count < 4))
            }

            Section("导入") {
                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("从文件导入")
                    }
                }
                if let url = importingURL, url.lastPathComponent.hasSuffix(".enc") {
                    SecureField("解密密码", text: $importPassword)
                    Button("解密并导入") { Task { await doImport(url: url) } }
                        .disabled(importPassword.isEmpty || working)
                }
            }

            if let s = statusMessage {
                Section {
                    Label(s, systemImage: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(statusOK ? .green : .red)
                }
            }
            if let sum = importSummary {
                Section("上次导入摘要") {
                    LabeledContent("Agents 新增", value: "\(sum.addedAgents)")
                    LabeledContent("对话新增", value: "\(sum.addedConversations)")
                    LabeledContent("消息新增", value: "\(sum.addedMessages)")
                    LabeledContent("源版本", value: "v\(sum.sourceVersion)")
                }
            }

            Section("说明") {
                Text("• 备份不包含 API Key（出于安全）。\n• 加密备份格式为 AES-GCM，文件后缀 `.hubibackup.enc`。\n• 导入采用增量合并（同 ID 跳过）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("备份")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data, .json, UTType(filenameExtension: "hubibackup") ?? .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importingURL = url
                if !url.lastPathComponent.hasSuffix(".enc") {
                    Task { await doImport(url: url) }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let u = exportURL { ShareSheet(items: [u]) }
        }
    }

    private func doExport() async {
        working = true; defer { working = false }
        do {
            let url = try BackupService.shared.exportToFile(
                context: context,
                password: encrypt ? password : nil
            )
            exportURL = url
            showShare = true
            statusOK = true
            statusMessage = "已生成 \(url.lastPathComponent)"
        } catch {
            statusOK = false
            statusMessage = error.localizedDescription
        }
    }

    private func doImport(url: URL) async {
        working = true; defer { working = false }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let summary = try BackupService.shared.importFromFile(
                url: url, context: context,
                password: importPassword.isEmpty ? nil : importPassword
            )
            importSummary = summary
            statusOK = true
            statusMessage = "导入成功"
            importingURL = nil
            importPassword = ""
        } catch {
            statusOK = false
            statusMessage = error.localizedDescription
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
