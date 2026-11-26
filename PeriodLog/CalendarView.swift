import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Day(Day().year, Day().month, 1)
    @State private var rangeStart: Day?
    @State private var rangeEnd: Day?
    @State private var feedback = 0
    private let rowHeight: CGFloat = 52
    private var firstWeekday: Int { (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? 2 : Calendar.current.firstWeekday }
    private var leading: Int { (Calendar(identifier: .gregorian).component(.weekday, from: month.localDate()) - firstWeekday + 7) % 7 }
    private var daysInMonth: Int { Day.arithmeticCalendar.range(of: .day, in: .month, for: month.localDate())?.count ?? 30 }
    private var weekLabels: [String] {
        let f = DateFormatter(); let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { symbols[(firstWeekday - 1 + $0) % 7] }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text(monthTitle).font(.title2.bold()).foregroundStyle(Design.ink)
                    Spacer()
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 44) }.accessibilityLabel(L.t("上个月")).accessibilityIdentifier("previousMonth")
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 44) }.accessibilityLabel(L.t("下个月")).accessibilityIdentifier("nextMonth")
                }
                HStack(spacing: 0) { ForEach(0..<7, id: \.self) { Text(weekLabels[$0]).font(.caption).foregroundStyle(Design.tertiary).frame(maxWidth: .infinity) } }
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { column in
                                    let index = row * 7 + column - leading
                                    if index >= 0 && index < daysInMonth { cell(month.adding(index)).frame(width: geometry.size.width / 7, height: rowHeight) }
                                    else { Color.clear.frame(width: geometry.size.width / 7, height: rowHeight) }
                                }
                            }
                        }
                    }.contentShape(Rectangle()).coordinateSpace(name: "monthGrid")
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("monthGrid")))
                            .onChanged { value in
                                if case .second(true, let drag?) = value {
                                    if rangeStart == nil { rangeStart = day(at: drag.startLocation, width: geometry.size.width); feedback += 1 }
                                    rangeEnd = day(at: drag.location, width: geometry.size.width)
                                }
                            })
                }.frame(height: rowHeight * 6).accessibilityElement(children: .contain).accessibilityIdentifier("calendarGrid")
                Legend()
                if let start = rangeStart, let end = rangeEnd {
                    VStack(spacing: 10) {
                        Text(L.range(min(start, end), max(start, end))).font(.subheadline)
                        HStack {
                            Button(L.t("标为经期")) { model.markPeriod(from: start, through: end, enabled: true); clearRange() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("markRangePeriod")
                            Button(L.t("取消经期")) { model.markPeriod(from: start, through: end, enabled: false); clearRange() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("clearRangePeriod")
                        }
                        Button(L.t("取消选择")) { clearRange() }.accessibilityIdentifier("cancelRange")
                    }.card()
                }
                selectedDayCard
                Disclaimer()
            }.padding(20)
        }.background(Design.background).sensoryFeedback(.selection, trigger: feedback)
            .onAppear { month = Day(model.today.year, model.today.month, 1) }
    }
    private var monthTitle: String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("yyyy MMMM"); return f.string(from: month.localDate())
    }
    private func move(_ delta: Int) { month = month.addingMonths(delta); clearRange() }
    private func clearRange() { rangeStart = nil; rangeEnd = nil }
    private func day(at point: CGPoint, width: CGFloat) -> Day? {
        guard point.x >= 0, point.x < width, point.y >= 0, point.y < rowHeight * 6 else { return nil }
        let index = Int(point.y / rowHeight) * 7 + Int(point.x / (width / 7)) - leading
        guard index >= 0, index < daysInMonth else { return nil }
        let day = month.adding(index); return day <= model.today ? day : model.today
    }
    private func cell(_ day: Day) -> some View {
        let log = model.log(on: day)
        let isPeriod = log.flow?.isPeriod == true
        let p = model.prediction
        let forecast = p?.future.contains { ($0.rangeStart...$0.rangeEnd).contains(day) } ?? false
        let fertile = p.map { ($0.fertileStart...$0.fertileEnd).contains(day) } ?? false
        let ovulation = p?.ovulation == day
        let selected = rangeStart.map { a in rangeEnd.map { (min(a, $0)...max(a, $0)).contains(day) } ?? (day == a) } ?? false
        let fill = isPeriod ? Design.primary : ovulation ? Design.pale : (fertile || selected) ? Design.faint : Color.clear
        return Button { model.selectedDay = day; clearRange(); feedback += 1 } label: {
            VStack(spacing: 3) {
                Text(String(day.day)).font(.body.weight(ovulation ? .semibold : .regular)).frame(width: 38, height: 38)
                    .foregroundStyle(isPeriod ? Color.white : (forecast || ovulation) ? Design.primary : Design.ink)
                    .background(fill, in: Circle())
                    .overlay { if forecast && !isPeriod { Circle().stroke(Design.primary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) } }
                    .overlay { if day == model.today { Circle().stroke(Design.ink, lineWidth: 2) } }
                    .overlay { if selected { Circle().stroke(Design.primary, lineWidth: 2) } }
                Circle().fill(log.hasRecord ? Design.tertiary : .clear).frame(width: 4, height: 4).accessibilityIdentifier("recordDot-" + day.description)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("calendar-" + day.description).accessibilityLabel(L.day(day, weekday: true) + (log.hasRecord ? L.t("，有记录") : "")).accessibilityValue(isPeriod ? L.t("经期") : "")
    }
    private var selectedDayCard: some View {
        let log = model.log(on: model.selectedDay)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.day(model.selectedDay, weekday: true)).font(.headline)
                Spacer()
                if let day = CycleCore.cycleDay(logs: model.data.logs, on: model.selectedDay) { Text(L.f("周期第 %@ 天", String(day))).font(.caption).foregroundStyle(Design.secondary) }
            }
            if log.hasRecord {
                if let flow = log.flow { Text(L.f("流量：%@", flow.title)).font(.subheadline) }
                Text((log.symptoms.sorted() + log.moods.sorted()).map(RecordOptions.title).joined(separator: " · ")).font(.subheadline).foregroundStyle(Design.secondary)
                if let bbt = log.bbt { Text(L.f("基础体温 %@ °C", String(format: "%.2f", Double(bbt) / 100))).font(.subheadline) }
                if !log.note.isEmpty { Text(log.note).font(.subheadline) }
            } else { Text(L.t("这一天还没有记录。")) .font(.subheadline).foregroundStyle(Design.secondary) }
            if model.selectedDay <= model.today { Button(L.t("编辑这一天")) { model.page = .day }.accessibilityIdentifier("editCalendarDay") }
            Text(L.t("长按拖动可以一次补记好几天经期。")) .font(.caption).foregroundStyle(Design.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
