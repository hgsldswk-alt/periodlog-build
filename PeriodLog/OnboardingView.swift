import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var lastStart = Date()
    @State private var knowsStart = true
    @State private var duration = 5
    @State private var cycle = 28
    @State private var irregular = false
    @State private var purpose: Purpose = .record
    @State private var importing = false
    private let titles = ["上次经期哪天开始？", "一般持续几天？", "周期通常多长？", "你想怎样使用？", "带上以前的记录"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text(L.t("隐私经期记录")).font(.headline); Spacer(); Text("\(step + 1) / 5").font(.caption).foregroundStyle(Design.secondary) }
            ProgressView(value: Double(step + 1), total: 5).tint(Design.primary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L.t(titles[step])).font(.largeTitle.bold()).foregroundStyle(Design.ink)
                    Text(L.t("不用注册。记录保存在你的手机。每一步都可以跳过。")) .foregroundStyle(Design.secondary)
                    stepContent
                }
            }
            HStack {
                if step > 0 { Button(L.t("上一步")) { step -= 1 }.accessibilityIdentifier("onboardingBack") }
                Spacer()
                Button(L.t("跳过")) { if step == 0 { knowsStart = false }; advance() }.accessibilityIdentifier("onboardingSkip")
            }
            Button(L.t(step == 4 ? "开始记录" : "继续")) { advance() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("onboardingNext")
        }.padding(24).background(Design.background).onAppear { lastStart = model.today.adding(-18).localDate() }.interactiveDismissDisabled().disabled(importing)
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            DatePicker(L.t("开始日期"), selection: $lastStart, in: ...model.today.localDate(hour: 23), displayedComponents: .date).datePickerStyle(.graphical).accessibilityIdentifier("onboardingLastPeriod")
            Toggle(L.t("我记得开始日期"), isOn: $knowsStart).accessibilityIdentifier("knowsStart")
            Button(L.t("记不清")) { knowsStart = false; advance() }.accessibilityIdentifier("dontRemember")
        case 1: Stepper(L.f("%@ 天", String(duration)), value: $duration, in: 1...14).accessibilityIdentifier("onboardingPeriodDays")
        case 2:
            Stepper(L.f("%@ 天", String(cycle)), value: $cycle, in: 15...90).accessibilityIdentifier("onboardingCycleDays")
            Toggle(L.t("不规律"), isOn: $irregular).accessibilityIdentifier("onboardingIrregular")
            Text(L.t("预测会显示大约范围，不需要记得很精确。")) .font(.subheadline).foregroundStyle(Design.secondary)
        case 3:
            ForEach(Purpose.allCases, id: \.rawValue) { item in
                Button { purpose = item } label: {
                    HStack { Text(item.title); Spacer(); Image(systemName: purpose == item ? "checkmark.circle.fill" : "circle") }.padding(18).background(Design.card, in: RoundedRectangle(cornerRadius: 16))
                }.accessibilityIdentifier("purpose-" + item.rawValue)
            }
        default:
            Text(L.t("如果以前的 App 写入过苹果健康，可以选择导入。不给权限也能正常记录。"))
            Button(L.t("从苹果健康导入历史")) {
                importing = true
                Task { await model.importHealth(); importing = false }
            }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("onboardingImportHealth")
            if !model.healthStatus.isEmpty { Text(model.healthStatus).font(.caption) }
        }
    }
    private func advance() {
        guard step == 4 else { step += 1; return }
        model.data.settings.periodDays = duration; model.data.settings.cycleDays = cycle
        model.data.settings.irregular = irregular; model.data.settings.purpose = purpose
        model.data.reminders.fertile = purpose == .conceive
        if knowsStart {
            let start = Day(date: lastStart)
            for n in 0..<duration where start.adding(n) <= model.today {
                var log = model.log(on: start.adding(n)); log.flow = n < 2 ? .medium : .light; model.data.upsert(log)
            }
            if start.distance(to: model.today) < duration { model.data.settings.openPeriodStart = start }
        }
        model.data.onboardingComplete = true; model.save(); model.page = nil
    }
}
