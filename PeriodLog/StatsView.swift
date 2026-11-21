import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPaywall = false
    @State private var activity: ActivityItem?
    @State private var reportCycles = 6
    private var stats: CycleStatistics { CycleCore.statistics(logs: model.data.logs) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L.t("统计")).font(.system(size: 28, weight: .bold))
                HStack(spacing: 12) {
                    average(L.t("平均周期"), value: stats.averageCycle)
                    average(L.t("平均经期"), value: stats.averagePeriod)
                }
                history
                if model.premium { advanced }
                else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("趋势、规律度、症状与体温图"))
                        HStack { Text(L.t("买断后可看")).font(.caption).foregroundStyle(Design.secondary); Spacer(); Button(L.t("了解买断")) { showPaywall = true }.accessibilityIdentifier("statsUpgrade") }
                    }.card()
                }
                Disclaimer()
            }.padding(20)
        }.background(Design.background).sheet(isPresented: $showPaywall) { PaywallView().environmentObject(model) }
            .sheet(item: $activity) { ActivitySheet(items: $0.items) }
    }
    private func average(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(Design.secondary)
            Text(value.map { L.f("%@ 天", String(format: "%.1f", $0)) } ?? "—").font(.system(.title, design: .rounded).weight(.semibold)).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("历史周期")).font(.headline)
            if model.periods.isEmpty { Text(L.t("记下经期后，这里会慢慢积累。")) .foregroundStyle(Design.secondary) }
            ForEach(Array(model.periods.enumerated().reversed()), id: \.element.id) { index, period in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.day(period.start)).font(.subheadline.weight(.semibold))
                        Text(L.f("经期 %@ 天", String(period.duration))).font(.caption).foregroundStyle(Design.secondary)
                    }
                    Spacer()
                    if index + 1 < model.periods.count {
                        let length = period.start.distance(to: model.periods[index + 1].start)
                        VStack(alignment: .trailing) {
                            Text(L.f("周期 %@ 天", String(length))).font(.subheadline)
                            if !(15...90).contains(length) { Text(L.t("未参与预测平均值")).font(.caption2).foregroundStyle(Design.secondary) }
                        }
                    } else { Text(L.t("当前周期")).font(.caption).foregroundStyle(Design.secondary) }
                }.accessibilityIdentifier("history-" + period.start.description)
                Divider()
            }
        }.card()
    }
    @ViewBuilder private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("周期长度趋势")).font(.headline)
            Chart {
                ForEach(Array(model.periods.dropLast().enumerated()), id: \.element.id) { index, period in
                    let length = period.start.distance(to: model.periods[index + 1].start)
                    LineMark(x: .value(L.t("日期"), period.start.localDate()), y: .value(L.t("天数"), length)).foregroundStyle(Design.primary)
                    PointMark(x: .value(L.t("日期"), period.start.localDate()), y: .value(L.t("天数"), length)).foregroundStyle(Design.primary)
                }
            }.frame(height: 190).accessibilityIdentifier("cycleChart")
            Text(L.f("规律度：%@", stats.regularity.title)).font(.subheadline)
            if let shortest = stats.shortest, let longest = stats.longest { Text(L.f("最短 %@ 天 · 最长 %@ 天", String(shortest), String(longest))).font(.caption).foregroundStyle(Design.secondary) }
        }.card()
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("身体感受与阶段")).font(.headline)
            ForEach(SymptomStage.allCases, id: \.rawValue) { stage in
                Text(stage.title).font(.subheadline.weight(.medium))
                let counts = stats.symptoms[stage] ?? []
                if counts.isEmpty { Text(L.t("暂无记录")).font(.caption).foregroundStyle(Design.secondary) }
                ForEach(Array(counts.prefix(5))) { count in HStack { Text(RecordOptions.title(count.key)); Spacer(); Text(L.f("%@ 次", String(count.count))) }.font(.caption).foregroundStyle(Design.secondary) }
            }
        }.card()
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("基础体温")).font(.headline)
            Chart {
                ForEach(Array(model.data.logs.filter { $0.bbt != nil }.suffix(120))) { log in
                    if let bbt = log.bbt { LineMark(x: .value(L.t("日期"), log.day.localDate()), y: .value("°C", Double(bbt) / 100)).foregroundStyle(Design.primary) }
                }
            }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 180).accessibilityIdentifier("temperatureChart")
        }.card()
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("周期汇总 PDF")).font(.headline)
            Picker(L.t("周期数量"), selection: $reportCycles) { Text(L.t("近 6 个周期")).tag(6); Text(L.t("近 12 个周期")).tag(12) }.pickerStyle(.segmented).accessibilityIdentifier("pdfCycles")
            Button(L.t("导出 PDF")) {
                do { let url = try CycleReport.export(data: model.data, cycles: reportCycles); activity = ActivityItem(items: [url]) }
                catch { model.message = L.t("导出失败，请稍后重试。") }
            }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("exportPDF")
        }.card()
    }
}
