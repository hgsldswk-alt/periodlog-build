import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-ui-testing", "-hide-paste-hint", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + arguments
        app.launch()
    }
    private func tap(_ id: String) {
        let button = app.buttons[id].firstMatch
        for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeUp() }
        if !button.isHittable { for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeDown() } }
        XCTAssertTrue(button.waitForExistence(timeout: 8), id); XCTAssertTrue(button.isHittable, id); button.tap()
    }
    private func closeSheet() {
        let buttons = app.buttons.matching(identifier: "closeSheet")
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5))
        let top = (0..<buttons.count).map { buttons.element(boundBy: $0) }.last { $0.isHittable }
        XCTAssertNotNil(top); top?.tap()
    }
    private func shot(_ name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
    private func dismissMessageIfPresent() {
        if app.alerts.firstMatch.waitForExistence(timeout: 2) { app.alerts.buttons["知道了"].tap() }
    }
    private func tab(_ label: String) { let button = app.tabBars.buttons[label]; XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap() }
    func testOnboardingCreatesPredictionWithoutPaywall() throws {
        launch(["-onboarding"])
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 8))
        for step in 1...5 {
            try shot("01-onboarding-\(step)")
            XCTAssertFalse(app.buttons["buyPro"].exists)
            tap("onboardingNext")
        }
        XCTAssertTrue(app.staticTexts["predictionRange"].waitForExistence(timeout: 8))
        try shot("02-first-prediction")
    }
    func testStartAndEndPeriod() throws {
        launch(["-uitest-fresh"])
        tap("periodAction"); try shot("03-choose-start"); tap("savePeriodDate")
        XCTAssertTrue(app.staticTexts["periodDay"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["periodDay"].label.contains("1")); try shot("04-period-day-one")
        tap("periodAction"); try shot("05-choose-end"); tap("savePeriodDate")
        tap("openDay"); XCTAssertTrue(app.buttons["closeSheet"].waitForExistence(timeout: 5)); try shot("06-period-ended-record"); closeSheet()
    }
    func testQuickSymptomPersistsInCalendar() throws {
        launch(["-uitest-fresh"])
        tap("quick-symptom-lowerBackPain"); try shot("07-quick-symptom")
        tab("日历")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "腰酸")).firstMatch.waitForExistence(timeout: 5))
        let recorded = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar-", "有记录")).firstMatch
        XCTAssertTrue(recorded.exists); try shot("08-calendar-record-dot")
    }
    func testCalendarLongPressDragMarksThreeDays() throws {
        launch(["-uitest-fresh", "-calendar"])
        let grid = app.otherElements["calendarGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        tap("previousMonth")
        let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar-"))
        let first = buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "-10")).firstMatch
        let last = buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "-12")).firstMatch
        XCTAssertTrue(first.exists); XCTAssertTrue(last.exists)
        first.press(forDuration: 0.6, thenDragTo: last)
        XCTAssertTrue(app.buttons["markRangePeriod"].waitForExistence(timeout: 5)); try shot("09-calendar-range")
        tap("markRangePeriod"); XCTAssertEqual(first.value as? String, "经期"); try shot("10-calendar-range-saved")
    }
    func testFriendCodeCreationAndInjectedPasteImport() throws {
        launch(["-demo", "-share-friend"])
        XCTAssertTrue(app.buttons["copyShareCode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.switches["shareIncludeDuration"].value as? String, "0")
        try shot("11-friend-card-default-privacy"); tap("copyShareCode"); dismissMessageIfPresent(); closeSheet()
        tap("openFriends"); XCTAssertTrue(app.buttons["pasteFriendCode"].exists); try shot("12-friends-paste-entry")
        app.terminate(); launch(["-uitest-fresh", "-import"])
        XCTAssertTrue(app.buttons["confirmImportCode"].waitForExistence(timeout: 8)); try shot("13-import-preview")
        tap("confirmImportCode"); XCTAssertTrue(app.staticTexts["friendImported"].waitForExistence(timeout: 5)); try shot("14-return-code-prompt")
        tap("viewImportedFriend")
        XCTAssertTrue(app.staticTexts["小雨"].waitForExistence(timeout: 5)); try shot("15-imported-friend-list")
    }
    func testPrivacyAndPaywallRestoreControls() throws {
        launch(["-uitest-fresh", "-settings", "-paid-mode"])
        let lock = app.switches["faceLock"]
        for _ in 0..<8 { if lock.exists && lock.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        lock.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let on = NSPredicate(format: "value == %@", "1")
        expectation(for: on, evaluatedWith: lock); waitForExpectations(timeout: 5)
        XCTAssertTrue(app.switches["discreetNotifications"].exists); try shot("16-privacy-settings")
        tap("openPaywall")
        XCTAssertTrue(app.buttons["restorePurchases"].waitForExistence(timeout: 5)); try shot("17-paywall")
    }
    func testLateExpiredAndLargestTextStates() throws {
        launch(["-demo", "-late"])
        XCTAssertTrue(app.staticTexts["countdown"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["countdown"].label.contains("4")); try shot("18-late-four-days")
        app.terminate(); launch(["-demo", "-expired"])
        XCTAssertTrue(app.staticTexts["expiredCopy"].waitForExistence(timeout: 8)); try shot("19-expired-free-records")
        app.terminate(); launch(["-demo", "-bigtext"])
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 8)); try shot("20-home-largest-text")
    }
}
