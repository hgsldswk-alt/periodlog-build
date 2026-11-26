import Foundation

enum Demo {
    static let today = Day(2026, 11, 15)
    static func data(irregular: Bool = false, late: Bool = false) -> AppData {
        var d = AppData(); d.onboardingComplete = true
        d.settings.nickname = L.t("小林"); d.settings.purpose = .conceive
        d.entitlement.purchasedPro = true
        var starts = [today.adding(late ? -34 : -18)]
        let intervals = irregular ? [24, 41, 26, 38, 29, 33, 25, 40] : [28, 28, 28, 28, 28, 28, 28, 28]
        for n in intervals { starts.insert(starts[0].adding(-n), at: 0) }
        for start in starts {
            for offset in 0..<5 { var l = DayLog(day: start.adding(offset)); l.flow = offset < 2 ? .medium : .light; if offset == 0 { l.symptoms = ["abdominalCramps"] }; d.logs.append(l) }
            for offset in 6..<19 {
                var l = DayLog(day: start.adding(offset)); l.bbt = offset < 15 ? 3635 + offset % 3 * 4 : 3665 + offset % 3 * 3
                if offset == 17 { l.symptoms = ["lowerBackPain"]; l.moods = ["calm"] }
                d.logs.append(l)
            }
        }
        d.logs.removeAll { $0.day > today }
        d.reminders.pill = true; d.reminders.pillStart = today.adding(-18)
        let names = [L.t("小雨"), L.t("阿哲")]
        for i in 0..<2 {
            let forecasts = (0..<3).map { offset in Forecast(start: today.adding(5 + offset * 28), rangeStart: today.adding(5 + offset * 28), rangeEnd: today.adding(8 + offset * 28), duration: nil) }
            d.friends.append(Friend(sourceID: UUID(), nickname: names[i], kind: i == 0 ? .friend : .partner, generated: today, predictions: forecasts, partnerTips: i == 1, remindDaysBefore: 1, importedAt: Date()))
        }
        d.normalize(); return d
    }
    static func incoming() -> ShareCode.Payload {
        ShareCode.Payload(kind: .friend, nickname: L.t("小雨"), generated: today, predictions: (0..<3).map { i in Forecast(start: today.adding(6 + i * 28), rangeStart: today.adding(4 + i * 28), rangeEnd: today.adding(8 + i * 28), duration: nil) }, partnerTips: false, sourceID: UUID(uuidString: "A135917D-88EE-42BB-8A98-111111111111")!)
    }
}
