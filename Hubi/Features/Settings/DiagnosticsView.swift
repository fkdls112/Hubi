import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppLogger.self) var logger

    var body: some View {
        List {
            Section {
                LabeledContent("App 版本",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                )
                LabeledContent("构建号",
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                )
            }
            Section("最近日志") {
                if logger.recentLogs.isEmpty {
                    Text("暂无日志").foregroundStyle(.secondary)
                } else {
                    ForEach(logger.recentLogs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(color(for: entry.level))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("诊断")
        .toolbar {
            ShareLink(item: logger.logFile) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func color(for level: AppLogger.Level) -> Color {
        switch level {
        case .debug:   return .gray
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
