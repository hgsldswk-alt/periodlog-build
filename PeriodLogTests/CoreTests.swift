import Foundation
import XCTest

final class CoreTests: XCTestCase {
    let start = Day(2026, 1, 1)
    func logs(_ lengths: [Int], duration: Int = 5) -> [DayLog] {
        var result: [DayLog] = []; var day = start
        for length in lengths + [0] {
            for i in 0..<duration { var l = DayLog(day: day.adding(i)); l.flow = .medium; if i == 0 { l.periodLink = .newPeriod }; result.append(l) }
            day = day.adding(length)
        }
        return result
    }
    func predict(_ lengths: [Int], settings: Settings = Settings(), late: Int = 0) throws -> Prediction {
        let records = logs(lengths)
        let last = CycleCore.periods(records).last!.start
        let today = last.adding(settings.cycleDays + late)
        return try XCTUnwrap(CycleCore.predict(logs: records, settings: settings, today: today))
    }
    func testDayArithmeticAcrossMonthYearLeapAndDST() throws {
        XCTAssertEqual(Day(2024, 2, 28).adding(1), Day(2024, 2, 29))
        XCTAssertEqual(Day(2024, 2, 29).adding(1), Day(2024, 3, 1))
        XCTAssertEqual(Day(2025, 12, 31).adding(1), Day(2026, 1, 1))
        XCTAssertEqual(Day(2026, 1, 1).adding(-1), Day(2025, 12, 31))
        XCTAssertEqual(Day(2026, 3, 7).distance(to: Day(2026, 3, 10)), 3)
        XCTAssertEqual(Day(2026, 11, 1).adding(1).adding(-1), Day(2026, 11, 1))
        XCTAssertNil(Day("2025-02-29")); XCTAssertNil(Day("2026-13-01")); XCTAssertNil(Day("2026-2-01"))
        let bytes = try JSONEncoder().encode(Day(2024, 2, 29))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "\"2024-02-29\"")
        XCTAssertEqual(try JSONDecoder().decode(Day.self, from: bytes), Day(2024, 2, 29))
    }
    func testCivilDateDoesNotShiftAfterTimeZoneChange() throws {
        let bytes = Data("\"2026-11-15\"".utf8)
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(secondsFromGMT: -11 * 3600)!
        let a = try JSONDecoder().decode(Day.self, from: bytes)
        NSTimeZone.default = TimeZone(secondsFromGMT: 14 * 3600)!
        XCTAssertEqual(try JSONDecoder().decode(Day.self, from: bytes), a)
    }
    func testPeriodInferenceMergesOneMissingDayButNotSpotting() {
        var a = DayLog(day: start); a.flow = .light
        var b = DayLog(day: start.adding(2)); b.flow = .heavy
        var c = DayLog(day: start.adding(20)); c.flow = .spotting
        let p = CycleCore.periods([c, b, a]); XCTAssertEqual(p.count, 1); XCTAssertEqual(p[0].duration, 3)
        XCTAssertTrue(CycleCore.periods([c]).isEmpty)
    }
    func testClosePeriodNeedsConfirmationAndCanContinue() {
        var values = logs([10], duration: 2)
        values[2].periodLink = .automatic
        XCTAssertTrue(CycleCore.periods(values)[1].needsConfirmation)
        values[2].periodLink = .newPeriod
        XCTAssertFalse(CycleCore.periods(values)[1].needsConfirmation)
        values[2].periodLink = .continuation
        XCTAssertEqual(CycleCore.periods(values).count, 1)
    }
    func testRegularPredictionAndThreeForecasts() throws {
        let p = try predict([28, 28, 28, 28, 28, 28, 28])
        XCTAssertEqual(p.cycleDays, 28); XCTAssertEqual(p.periodDays, 5)
        XCTAssertEqual(p.rangeStart.distance(to: p.rangeEnd), 4)
        XCTAssertEqual(p.regularity, .regular); XCTAssertEqual(p.future.count, 3)
        XCTAssertEqual(p.ovulation, p.nextStart.adding(-14))
        XCTAssertEqual(p.fertileStart, p.ovulation.adding(-5)); XCTAssertEqual(p.fertileEnd, p.ovulation.adding(1))
        XCTAssertTrue(p.matchedLastPeriod)
    }
    func testWeightedMeanAndLastSixOnly() throws {
        let p = try predict([20, 40]); XCTAssertEqual(p.cycleDays, 31)
        let a = try predict([15, 20, 30, 40, 50, 60, 70])
        let b = try predict([20, 30, 40, 50, 60, 70])
        XCTAssertEqual(a.cycleDays, b.cycleDays); XCTAssertEqual(a.cycleDays, 53)
    }
    func testIrregularAndOutlierExclusion() throws {
        let p = try predict([24, 41, 26, 38]); XCTAssertEqual(p.regularity, .irregular)
        XCTAssertGreaterThan(p.rangeStart.distance(to: p.rangeEnd), 4)
        let outliers = try predict([28, 10, 100, 28]); XCTAssertEqual(outliers.cycleDays, 28)
        let statistics = CycleCore.statistics(logs: logs([28, 10, 100, 28]))
        XCTAssertEqual(statistics.shortest, 10); XCTAssertEqual(statistics.longest, 100)
    }
    func testZeroAndOneCompleteCycleUseSettingsPlusMinusThree() throws {
        var s = Settings(); s.cycleDays = 31
        XCTAssertEqual(try predict([], settings: s).cycleDays, 31)
        let p = try predict([24], settings: s)
        XCTAssertEqual(p.cycleDays, 31); XCTAssertEqual(p.rangeStart.distance(to: p.rangeEnd), 6)
        XCTAssertNil(CycleCore.predict(logs: [], settings: s, today: start))
    }
    func testRangeMinimumAndMedianPeriodDuration() throws {
        var values = logs([28, 29], duration: 3)
        for i in 3..<7 { var l = DayLog(day: start.adding(i)); l.flow = .light; values.append(l) }
        let p = try XCTUnwrap(CycleCore.predict(logs: values, settings: Settings(), today: start.adding(80)))
        XCTAssertEqual(p.periodDays, 3); XCTAssertEqual(p.rangeStart.distance(to: p.rangeEnd), 4)
    }
    func testOvulationCorrectionPauseAndRecordOnly() throws {
        var s = Settings(); s.purpose = .conceive
        var values = logs([28, 28]); var l = DayLog(day: start.adding(70)); l.ovulationTest = .positive; values.append(l)
        let p = try XCTUnwrap(CycleCore.predict(logs: values, settings: s, today: start.adding(72)))
        XCTAssertEqual(p.ovulation, start.adding(71))
        s.pauseReason = .breastfeeding; XCTAssertNil(CycleCore.predict(logs: values, settings: s, today: start.adding(72)))
        s.pauseReason = nil; s.recordOnly = true; XCTAssertNil(CycleCore.predict(logs: values, settings: s, today: start.adding(72)))
        s.recordOnly = false; s.predictionRestart = start.adding(100)
        XCTAssertNil(CycleCore.predict(logs: values, settings: s, today: start.adding(100)))
    }
    func testLateDaysAccuracyAndPhases() throws {
        let p = try predict([28, 28], late: 6); XCTAssertEqual(p.lateDays, 4)
        let values = logs([28, 28]); let s = Settings()
        XCTAssertEqual(CycleCore.cycleDay(logs: values, on: start.adding(74)), 19)
        XCTAssertEqual(CycleCore.phase(logs: values, settings: s, on: start.adding(56), prediction: p), .period)
        XCTAssertEqual(CycleCore.phase(logs: values, settings: s, on: p.ovulation, prediction: p), .ovulation)
        XCTAssertEqual(CycleCore.phase(logs: values, settings: s, on: p.fertileStart, prediction: p), .fertile)
        XCTAssertEqual(CycleCore.phase(logs: values, settings: s, on: p.rangeEnd.adding(1), prediction: p), .late)
        XCTAssertFalse(try predict([28, 28, 45]).matchedLastPeriod)
    }
    func testStatisticsAndSymptomStageSorting() {
        var values = logs([28, 30])
        for day in [start.adding(-2), start.adding(-1), start.adding(1), start.adding(10)] {
            var l = DayLog(day: day); l.symptoms = ["headache"]
            if day == start.adding(-1) { l.symptoms.insert("fatigue") }
            if let i = values.firstIndex(where: { $0.day == day }) { values[i].symptoms = l.symptoms } else { values.append(l) }
        }
        let s = CycleCore.statistics(logs: values)
        XCTAssertEqual(s.averageCycle, 29); XCTAssertEqual(s.averagePeriod, 5)
        XCTAssertEqual(s.shortest, 28); XCTAssertEqual(s.longest, 30)
        XCTAssertEqual(s.symptoms[.before]?.first, SymptomCount(key: "headache", count: 2))
        XCTAssertEqual(s.symptoms[.during]?.first?.count, 1); XCTAssertEqual(s.symptoms[.other]?.first?.count, 1)
    }
    func testTemperatureRequiresThreeConsecutiveRaisedDays() {
        var values: [DayLog] = []
        for i in 0..<9 { var l = DayLog(day: start.adding(i)); l.bbt = i < 6 ? 3630 : 3660; values.append(l) }
        XCTAssertTrue(CycleCore.temperatureRaised(values, today: start.adding(8)))
        values.removeLast(); XCTAssertFalse(CycleCore.temperatureRaised(values, today: start.adding(8)))
    }
    func testMissingFieldsAndStoreAtomicRoundTrip() throws {
        let bytes = Data("{\"logs\":[{\"day\":\"2026-01-01\",\"flow\":\"light\"}]}".utf8)
        let d = try JSONDecoder().decode(AppData.self, from: bytes)
        XCTAssertTrue(d.settings.discreetNotifications); XCTAssertFalse(d.settings.cloudEnabled)
        XCTAssertEqual(d.logs[0].symptoms, [])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("records.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = Store(url: url); try store.save(d)
        XCTAssertEqual(try store.load(), d)
        try Data("broken".utf8).write(to: url); XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }
    func testPaidEraTrialStartsAtPaidVersionLaunch() {
        let install = Date(timeIntervalSince1970: 1_800_000_000)
        let paidLaunch = install.addingTimeInterval(90 * 86400)
        var e = Entitlement(firstOpen: install, proStartedAt: paidLaunch)
        XCTAssertEqual(e.trialStart, paidLaunch)
        XCTAssertTrue(e.isPremium(at: paidLaunch.addingTimeInterval(29 * 86400)))
        XCTAssertFalse(e.isPremium(at: paidLaunch.addingTimeInterval(31 * 86400)))
        e.trialClaimedAt = install.addingTimeInterval(100 * 86400)
        XCTAssertEqual(e.trialStart, install)
        XCTAssertTrue(Entitlement(firstOpen: install).hasPro(at: install) || !Launch.freePeriod)
        if Launch.freePeriod { XCTAssertTrue(Entitlement(firstOpen: install).hasPro(at: install.addingTimeInterval(400 * 86400))) }
    }
    func testTrialToleranceExpiryAndPillContinuity() {
        let now = Date(); let e = Entitlement(firstOpen: now, proStartedAt: now)
        XCTAssertTrue(e.isPremium(at: now.addingTimeInterval(-599))); XCTAssertFalse(e.isPremium(at: now.addingTimeInterval(-601)))
        XCTAssertTrue(e.isPremium(at: now)); XCTAssertFalse(e.isPremium(at: e.trialEnd))
        XCTAssertEqual(e.remainingDays(at: now), 30)
        XCTAssertEqual(e.canUsePillReminder(at: e.trialEnd), Launch.freePeriod); XCTAssertTrue(e.canDeliverExistingPillReminder(enabled: true))
        var claimed = e; claimed.trialClaimedAt = now.addingTimeInterval(86400 * 40)
        XCTAssertEqual(claimed.trialEnd, e.trialEnd)
        claimed.purchasedPro = true; XCTAssertTrue(claimed.canUseWidget(at: e.trialEnd))
    }
    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testReviewConditionsAndMilestonesDoNotRepeat() {
        let periods = CycleCore.periods(logs([28]))
        XCTAssertEqual(ReviewGate.condition(periods: periods, matched: true, milestone: nil, requested: []), "second-match")
        XCTAssertNil(ReviewGate.condition(periods: periods, matched: true, milestone: nil, requested: ["second-match"]))
        XCTAssertEqual(Milestone.next(periods: CycleCore.periods(logs([28, 28])), shown: []), 3)
        XCTAssertNil(Milestone.next(periods: CycleCore.periods(logs([28, 28])), shown: [3]))
        XCTAssertEqual(ReviewGate.condition(periods: [], matched: false, milestone: 3, requested: []), "first-milestone")
        XCTAssertNil(ReviewGate.condition(periods: [], matched: false, milestone: 6, requested: ["first-milestone"]))
        XCTAssertEqual(Milestone.consecutiveCycles(CycleCore.periods(logs([28, 100, 28]))), 2)
    }
}
