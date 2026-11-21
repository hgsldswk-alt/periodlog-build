import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    private let benefits = ["把变化整理成趋势，看得更清楚", "导出一份清楚的周期汇总 PDF", "吃药、记录与易孕期提醒", "自己的 iCloud 备份与桌面小组件", "自定义症状与中性图标"]
    var body: some View {
        SheetFrame(title: L.t("一次买断")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L.t("记录安心，长期也从容")).font(.largeTitle.bold()).foregroundStyle(Design.ink)
                    if model.data.entitlement.purchasedPro { Text(L.t("高级功能已买断，感谢你的支持。")) }
                    else if model.premium { Text(L.f("高级体验还剩 %@ 天", String(model.data.entitlement.remainingDays(at: model.now)))).accessibilityIdentifier("trialRemaining") }
                    else { Text(L.t("高级体验已结束。记录永远免费，已建吃药提醒照常。")) .accessibilityIdentifier("expiredCopy") }
                    ForEach(benefits, id: \.self) { Text(L.t($0)).frame(maxWidth: .infinity, alignment: .leading).card() }
                    Text(L.t("记录、预测、日历、CSV、备份、面容锁与亲友口令永远免费。")) .font(.subheadline).foregroundStyle(Design.secondary)
                    Button(model.products.first(where: { $0.id == model.proID }).map { L.f("%@ 一次买断", $0.displayPrice) } ?? L.t("买断高级功能")) { Task { await model.purchase(model.proID) } }.buttonStyle(PrimaryButtonStyle()).disabled(model.purchasing || !model.products.contains { $0.id == model.proID }).accessibilityIdentifier("buyPro")
                    if !model.data.entitlement.purchasedPro && model.data.entitlement.trialClaimedAt == nil && model.data.entitlement.remainingDays(at: model.now) > 0 {
                        Button(L.t("保存 30 天免费体验")) { Task { await model.purchase(model.trialID) } }.disabled(model.purchasing || !model.products.contains { $0.id == model.trialID }).accessibilityIdentifier("claimTrial")
                    }
                    Text(L.t("免费体验从首次打开起共 30 天，恢复后沿用原到期时间。一次购买，不自动续费。")) .font(.caption).foregroundStyle(Design.secondary)
                    Button(L.t("恢复购买")) { Task { await model.restorePurchases() } }.accessibilityIdentifier("restorePurchases")
                    Button(L.t("重新加载商品")) { Task { await model.loadProducts() } }.accessibilityIdentifier("reloadProducts")
                }.padding(24)
            }
        }.task { await model.loadProducts() }
            .onAppear { if !model.premium { model.data.expiryNoticeShown = true; model.save() } }
    }
}
