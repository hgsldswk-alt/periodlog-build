import SwiftUI
import WidgetKit

struct PeriodEntry: TimelineEntry {
    var date: Date
    var data: AppData
}
struct PeriodProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeriodEntry { PeriodEntry(date: Demo.today.localDate(), data: Demo.data()) }
    func getSnapshot(in context: Context, completion: @escaping (PeriodEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : PeriodEntry(date: Date(), data: (try? Store().load()) ?? AppData()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PeriodEntry>) -> Void) {
        let data = (try? Store().load()) ?? AppData(), now = Date()
        let entries = (0..<24).map { PeriodEntry(date: now.addingTimeInterval(Double($0) * 3600), data: data) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
struct PeriodWidgetView: View {
    let entry: PeriodEntry
    @Environment(\.widgetFamily) private var family
    private let color = Color(red: 180.0 / 255, green: 85.0 / 255, blue: 63.0 / 255)
    private var today: Day { Day(date: entry.date) }
    private var prediction: Prediction? { CycleCore.predict(logs: entry.data.logs, settings: entry.data.settings, today: today) }
    private var period: Bool { CycleCore.phase(logs: entry.data.logs, settings: entry.data.settings, on: today, prediction: prediction) == .period }
    private var count: Int {
        if period { return CycleCore.cycleDay(logs: entry.data.logs, on: today) ?? 1 }
        return prediction.map { max(0, today.distance(to: $0.nextStart)) } ?? 0
    }
    private var title: String {
        if entry.data.settings.discreetWidget { return String(count) }
        if entry.data.settings.pauseReason != nil || entry.data.settings.recordOnly { return L.t("已暂停预测") }
        guard prediction != nil || period else { return L.t("从一笔记录开始") }
        return period ? L.f("经期第 %@ 天", String(count)) : L.f("距下次约 %@ 天", String(count))
    }
    var body: some View {
        Group {
            if entry.data.entitlement.canUseWidget(at: entry.date) { content }
            else { Text(L.t("买断后可用小组件")).font(.caption).multilineTextAlignment(.center).minimumScaleFactor(0.6) }
        }.containerBackground(for: .widget) { Color(uiColor: .secondarySystemBackground) }.widgetURL(URL(string: "periodlog://today"))
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.data.settings.discreetWidget ? String(count) + " ·" : title)
        case .accessoryCircular:
            ZStack {
                Circle().stroke(.secondary.opacity(0.2), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(min(28, count)) / 28).stroke(.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(String(count)).font(.system(.title3, design: .rounded).weight(.semibold))
            }
        case .systemMedium:
            HStack(spacing: 20) {
                miniRing.frame(width: 75, height: 75)
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.headline).minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        ForEach(-3...3, id: \.self) { offset in
                            let day = today.adding(offset)
                            VStack(spacing: 4) {
                                Text(String(day.day)).font(.caption2.monospacedDigit())
                                Circle().fill(offset == 0 ? color : .secondary.opacity(0.3)).frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }
        default:
            VStack(spacing: 10) { miniRing.frame(width: 65, height: 65); Text(title).font(.caption).multilineTextAlignment(.center).minimumScaleFactor(0.6) }
        }
    }
    private var miniRing: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(28, max(1, count))) / 28).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(String(count)).font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(color)
        }.accessibilityLabel(title)
    }
}
@main struct PeriodLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PeriodLogWidget", provider: PeriodProvider()) { PeriodWidgetView(entry: $0) }
            .configurationDisplayName(L.t("经期记录"))
            .description(L.t("随时查看大约日期，也可只显示数字。"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}
