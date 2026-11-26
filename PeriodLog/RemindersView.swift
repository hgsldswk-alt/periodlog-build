import SwiftUI

struct RemindersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPaywall = false
    var body: some View {
        Form {
            Section(L.t("经期提醒（免费）")) {
                Toggle(L.t("下次经期提醒"), isOn: freeToggle(\.nextPeriod)).accessibilityIdentifier("nextPeriodReminder")
                Stepper(L.f("提前 %@ 天", String(model.data.reminders.daysBefore)), value: model.reminder(\.daysBefore), in: 0...7).accessibilityIdentifier("periodReminderDays")
                Toggle(L.t("预计开始后询问是否忘记记录"), isOn: freeToggle(\.late)).accessibilityIdentifier("lateReminder")
            }
            Section(L.t("其他提醒")) {
                Toggle(L.t("易孕期开始"), isOn: advancedToggle(\.fertile)).accessibilityIdentifier("fertileReminder")
                Toggle(L.t("每日记录提醒"), isOn: advancedToggle(\.daily)).accessibilityIdentifier("dailyReminder")
                DatePicker(L.t("记录时间"), selection: time(hour: \.dailyHour, minute: \.dailyMinute), displayedComponents: .hourAndMinute).disabled(!model.premium).accessibilityIdentifier("dailyTime")
            }
            Section(L.t("吃药提醒")) {
                Toggle(L.t("每天提醒吃药"), isOn: advancedToggle(\.pill)).accessibilityIdentifier("pillReminder")
                Group {
                    DatePicker(L.t("吃药时间"), selection: time(hour: \.pillHour, minute: \.pillMinute), displayedComponents: .hourAndMinute).accessibilityIdentifier("pillTime")
                    Picker(L.t("服用模式"), selection: model.reminder(\.pillMode)) { ForEach(PillMode.allCases, id: \.rawValue) { Text($0.title).tag($0) } }.accessibilityIdentifier("pillMode")
                    DatePicker(L.t("起始日"), selection: Binding(get: { model.data.reminders.pillStart.localDate() }, set: { model.data.reminders.pillStart = Day(date: $0); model.save() }), displayedComponents: .date).accessibilityIdentifier("pillStart")
                }.disabled(!model.premium)
                Text(L.t("2 小时后仍未记录已吃，会再提醒一次。试用到期后，已建吃药提醒照常响；新建或修改需要买断。")) .font(.caption).foregroundStyle(Design.secondary)
                if !model.premium { Button(L.t("了解买断")) { showPaywall = true }.accessibilityIdentifier("reminderUpgrade") }
            }
            Section {
                Toggle(L.t("隐晦通知文案"), isOn: model.setting(\.discreetNotifications)).accessibilityIdentifier("reminderDiscreet")
                Button(L.t("开启通知权限")) { Task { await model.askNotifications() } }.accessibilityIdentifier("requestNotifications")
                if model.notificationDenied { Link(L.t("通知未开启 · 去设置"), destination: URL(string: UIApplication.openSettingsURLString)!).accessibilityIdentifier("notificationSettings") }
                Text(L.t("提醒只在本机安排。打开 App 后会自动更新后续提醒。")) .font(.caption).foregroundStyle(Design.secondary)
            }
            Disclaimer()
        }.scrollContentBackground(.hidden).background(Design.background).navigationTitle(L.t("提醒")).sheet(isPresented: $showPaywall) { PaywallView().environmentObject(model) }
    }
    private func freeToggle(_ key: WritableKeyPath<Reminders, Bool>) -> Binding<Bool> {
        Binding(get: { model.data.reminders[keyPath: key] }, set: { enabled in model.data.reminders[keyPath: key] = enabled; model.save(); if enabled { Task { await model.askNotifications() } } })
    }
    private func advancedToggle(_ key: WritableKeyPath<Reminders, Bool>) -> Binding<Bool> {
        Binding(get: { model.data.reminders[keyPath: key] }, set: { enabled in
            if enabled && !model.premium { showPaywall = true; return }
            model.data.reminders[keyPath: key] = enabled; model.save(); if enabled { Task { await model.askNotifications() } }
        })
    }
    private func time(hour: WritableKeyPath<Reminders, Int>, minute: WritableKeyPath<Reminders, Int>) -> Binding<Date> {
        Binding(get: { model.today.localDate(hour: model.data.reminders[keyPath: hour], minute: model.data.reminders[keyPath: minute]) }, set: { date in
            guard model.premium else { showPaywall = true; return }
            model.data.reminders[keyPath: hour] = Calendar.current.component(.hour, from: date)
            model.data.reminders[keyPath: minute] = Calendar.current.component(.minute, from: date); model.save()
        })
    }
}
