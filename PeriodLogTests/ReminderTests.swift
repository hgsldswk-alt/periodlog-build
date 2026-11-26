import XCTest

final class ReminderTests: XCTestCase {
    func testPlanIsCappedDiscreetAndPillSurvivesExpiry() {
        var d = Demo.data(); let now = Demo.today.localDate(hour: 7)
        d.entitlement = Entitlement(firstOpen: now.addingTimeInterval(-40 * 86400), proStartedAt: now.addingTimeInterval(-40 * 86400))
        d.reminders.daily = true; d.reminders.fertile = true
        let plan = ReminderPlan.make(data: d, now: now)
        XCTAssertLessThanOrEqual(plan.count, 64)
        XCTAssertTrue(plan.contains { $0.id.hasPrefix("pill-") })
        XCTAssertEqual(plan.contains { $0.id.hasPrefix("daily-") || $0.id.hasPrefix("fertile-") }, Launch.freePeriod)
        XCTAssertTrue(plan.allSatisfy { $0.title == L.t("日历提醒") })
        XCTAssertFalse(plan.contains { $0.body.contains("经期") || $0.body.contains("吃药") })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        d.settings.discreetNotifications = false
        XCTAssertTrue(ReminderPlan.make(data: d, now: now).contains { $0.body == L.t("到记录吃药的时间了。") })
    }
    func testPillModesAndFollowupCancelledWhenTaken() {
        XCTAssertTrue(PillMode.days21and7.isActive(offset: 20)); XCTAssertFalse(PillMode.days21and7.isActive(offset: 21))
        XCTAssertTrue(PillMode.days21and7.isActive(offset: 28))
        XCTAssertFalse(PillMode.days24and4.isActive(offset: 24)); XCTAssertTrue(PillMode.days28.isActive(offset: 27))
        XCTAssertFalse(PillMode.continuous.isActive(offset: -1))
        var d = Demo.data(); var l = DayLog(day: Demo.today); l.pillTaken = true; d.upsert(l)
        let plan = ReminderPlan.make(data: d, now: Demo.today.localDate(hour: 7))
        XCTAssertFalse(plan.contains { $0.id == "pill-" + Demo.today.description || $0.id == "pill-followup-" + Demo.today.description })
    }
    func testLateSnoozesStopAfterTwoAndFutureRemindersAreLocalDates() throws {
        var d = Demo.data(); d.reminders.pill = false
        let p = try XCTUnwrap(CycleCore.predict(logs: d.logs, settings: d.settings, today: Demo.today))
        d.reminders.lateResponses[p.nextStart.description] = 3
        XCTAssertFalse(ReminderPlan.make(data: d, now: Demo.today.localDate()).contains { $0.category == "PERIOD_CHECK" })
        d.reminders.lateResponses[p.nextStart.description] = 1; d.reminders.lateSnoozedUntil = Demo.today.adding(3)
        let late = try XCTUnwrap(ReminderPlan.make(data: d, now: Demo.today.localDate()).first { $0.category == "PERIOD_CHECK" })
        XCTAssertEqual(late.day, Demo.today.adding(3))
        let parts = Calendar.current.dateComponents([.hour, .minute], from: late.date); XCTAssertEqual(parts.hour, 9); XCTAssertEqual(parts.minute, 0)
    }
}
