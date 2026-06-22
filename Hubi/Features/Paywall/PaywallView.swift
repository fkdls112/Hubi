import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = StoreKitManager.shared
    @State private var entitlement = EntitlementStore.shared
    @State private var selectedID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    benefitsSection
                    productsSection
                    actionsSection
                    legalSection
                }
                .padding()
            }
            .navigationTitle("解锁 Hub-i")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await manager.loadProducts() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange.gradient)
            Text("Hub-i 高级版")
                .font(.title.bold())
            Text("一次付费 · 终身解锁")
                .foregroundStyle(.secondary)
            Text("当前: \(entitlement.currentTier.displayName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(icon: "checkmark.seal.fill",
                       title: "全部预设模板",
                       detail: "OpenAI、Claude、Gemini、DeepSeek 等一键开箱即用")
            BenefitRow(icon: "wand.and.stars",
                       title: "预设智能体",
                       detail: "翻译官、灵感写手、研究员等开箱即用")
            BenefitRow(icon: "infinity",
                       title: "免费版同样强大",
                       detail: "免费版可手动配置任意自定义模型，能力不打折")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var productsSection: some View {
        VStack(spacing: 10) {
            if manager.products.isEmpty {
                ProgressView("加载产品中...")
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(manager.products, id: \.id) { product in
                    ProductCard(
                        product: product,
                        selected: selectedID == product.id,
                        currentTier: entitlement.currentTier
                    ) {
                        selectedID = product.id
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase() }
            } label: {
                HStack {
                    if manager.purchaseInProgress { ProgressView().tint(.white) }
                    Text(selectedID == nil ? "请选择套餐" : "立即购买")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedID == nil ? Color.gray : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedID == nil || manager.purchaseInProgress)

            HStack {
                Button("恢复购买") { Task { await manager.restore() } }
            }
            .font(.footnote)

            if let err = manager.lastError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
    }

    private var legalSection: some View {
        VStack(spacing: 6) {
            Text("一次性付费，永久有效，非订阅、不自动续费。")
            Text("[隐私政策](https://hubi.623101.xyz/privacy) · [使用条款](https://hubi.623101.xyz/eula)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private func purchase() async {
        guard let id = selectedID,
              let product = manager.products.first(where: { $0.id == id }) else { return }
        switch await manager.purchase(product) {
        case .success: dismiss()
        case .cancelled, .pending, .failed: break
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProductCard: View {
    let product: Product
    let selected: Bool
    let currentTier: HubiTier
    let action: () -> Void

    var isCurrent: Bool { currentTier == .premium }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(.headline)
                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(product.displayPrice).font(.title3.bold())
                    Text("终身").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color(.systemGray4),
                            lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Text("已解锁")
                    .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.green).foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }
}
