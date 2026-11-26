import Foundation

struct PlannedReminder: Equatable, Identifiable {
    var id: String
    var date: Date
    var title: String
    var body: String
    var category: String
    var day: Day
}
enum ReminderPlan {
    static func make(data: AppData, now: Date) -> [PlannedReminder] {
        let today = Day(date: now), r = data.reminders
        let premium = data.entitlement.hasPro(at: now)
        let p = CycleCore.predict(logs: data.logs, settings: data.settings, today: today)
        var result: [PlannedReminder] = []
        func add(_ id: String, _ day: Day, _ hour: Int, _ minute: Int, _ body: String, _ category: String = "", friend: Bool = false, offset: TimeInterval = 0) {
            let date = day.localDate(hour: hour, minute: minute).addingTimeInterval(offset)
            guard date > now else { return }
            let title = data.settings.discreetNotifications ? L.t("日历提醒") : L.t("经期记录")
            let text = data.settings.discreetNotifications ? L.t(friend ? "有一条亲友提醒" : category == "PILL" ? "到时间了，记得看看。" : "记得看看今天的日历。") : body
            result.append(PlannedReminder(id: id, date: date, title: title, body: text, category: category, day: day))
        }
        if let p = p {
            if r.nextPeriod {
                for f in p.future { add("period-" + f.start.description, f.start.adding(-r.daysBefore), 9, 0, L.t("下次经期大约快到了，可以提前准备。")) }
            }
            if r.late {
                let key = p.nextStart.description
                let count = r.lateResponses[key, default: 0]
                let lateDay = r.lateSnoozedUntil ?? p.nextStart.adding(2)
                if count <= 2 {
                    let due = max(lateDay, today)
                    add("late-" + key, due, due == today ? min(23, Calendar.current.component(.hour, from: now) + 1) : 9, 0, L.t("经期开始了吗？可以补记是哪天开始的。"), "PERIOD_CHECK")
                }
            }
            if r.fertile && premium { add("fertile-" + p.fertileStart.description, p.fertileStart, 9, 0, L.t("预计易孕期开始，预测仅供参考。")) }
        }
        for f in data.friends {
            guard let before = f.remindDaysBefore, !f.isStale(on: today) else { continue }
            for prediction in f.predictions {
                add("friend-" + f.id.uuidString + "-" + prediction.start.description, prediction.start.adding(-max(0, min(7, before))), 9, 0, L.f("%@ 的经期大约快到了，可以问问她需不需要什么。", f.nickname), friend: true)
            }
        }
        for offset in 0..<60 {
            let day = today.adding(offset)
            if r.daily && premium { add("daily-" + day.description, day, r.dailyHour, r.dailyMinute, L.t("今天感觉怎么样？记一笔吧。")) }
            if data.entitlement.canDeliverExistingPillReminder(enabled: r.pill), r.pillMode.isActive(offset: r.pillStart.distance(to: day)),
               data.logs.first(where: { $0.day == day })?.pillTaken != true {
                add("pill-" + day.description, day, r.pillHour, r.pillMinute, L.t("到记录吃药的时间了。"), "PILL")
                add("pill-followup-" + day.description, day, r.pillHour, r.pillMinute, L.t("还没有记录已吃，记得看看。"), "PILL", offset: 7200)
            }
        }
        return Array(result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(64))
    }
}
