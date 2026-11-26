import SwiftUI
import StoreKit
import WidgetKit

enum Page: String, Identifiable { case day, start, friends, shareFriend, sharePartner, invite, milestone, importCode, settings, paywall, onboarding, reminders, backup
    var id: String { rawValue }
}
@MainActor final class AppModel: ObservableObject {
    @Published var data: AppData
    @Published var now: Date
    @Published var selectedDay: Day
    @Published var tab = 0
    @Published var page: Page?
    @Published var message: String?
    @Published var incoming: ShareCode.Payload?
    @Published var importedFriendID: UUID?
    @Published var cloudRestore: AppData?
    @Published var products: [Product] = []
    @Published var purchasing = false
    @Published private(set) var reviewCondition: String?
    @Published var pasteAvailable = false
    @Published var notificationDenied = false
    @Published var healthStatus = ""
    @Published var pendingMilestone: Int?
    @Published var loadFailed = false
    let store: Store
    let isolated: Bool
    let demo: Bool
    let scheduler = ReminderScheduler()
    let health = HealthKitSync()
    private var purchasesTask: Task<Void, Never>?
    private var schedulingTask: Task<Void, Never>?
    private var lastPasteChange = -1
    private var cloudObserver: NSObjectProtocol?
    private var started = false
    var today: Day { demo ? Demo.today : Day(date: now) }
    var premium: Bool { data.entitlement.hasPro(at: now) }
    var prediction: Prediction? { CycleCore.predict(logs: data.logs, settings: data.settings, today: today) }
    var periods: [Period] { CycleCore.periods(data.logs) }
    var phase: CyclePhase { CycleCore.phase(logs: data.logs, settings: data.settings, on: today, prediction: prediction) }
    var proID: String { Bundle.main.object(forInfoDictionaryKey: "PeriodLogProProductID") as? String ?? "com.hgsldswk.periodlog.pro" }
    var trialID: String { Bundle.main.object(forInfoDictionaryKey: "PeriodLogTrialProductID") as? String ?? "com.hgsldswk.periodlog.trial" }
    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = args.contains("-demo") || args.contains("-demo-irregular") || args.contains("-late")
        isolated = demo || args.contains("-uitest-fresh") || args.contains("-onboarding") || args.contains("-ui-testing")
        store = Store(); now = Date(); selectedDay = Day()
        if demo { data = Demo.data(irregular: args.contains("-demo-irregular"), late: args.contains("-late")) }
        else if isolated { data = AppData(); data.onboardingComplete = !args.contains("-onboarding") }
        else {
            do { data = try store.load() }
            catch { data = AppData(); data.onboardingComplete = true; loadFailed = true; message = L.t("无法读取本地文件，原文件已保留。请重新打开 App，或从备份恢复。") }
        }
        now = demo ? Demo.today.localDate() : Date(); selectedDay = today
        if !Launch.freePeriod && data.entitlement.proStartedAt == nil { data.entitlement.proStartedAt = now; if !isolated { try? store.save(data) } }
        if args.contains("-expired") { data.entitlement = Entitlement(firstOpen: now.addingTimeInterval(-40 * 86400), proStartedAt: now.addingTimeInterval(-40 * 86400)); data.expiryNoticeShown = false }
        if args.contains("-calendar") { tab = 1 }
        if args.contains("-stats") { tab = 2 }
        let routes: [(String, Page)] = [("-day", .day), ("-share-friend", .shareFriend), ("-share-partner", .sharePartner), ("-invite", .invite), ("-milestone", .milestone), ("-friends", .friends), ("-import", .importCode), ("-settings", .settings), ("-paywall", .paywall), ("-expired", .paywall), ("-onboarding", .onboarding), ("-reminders", .reminders), ("-backup", .backup)]
        for route in routes where args.contains(route.0) { page = route.1 }
        if args.contains("-import") { incoming = Demo.incoming() }
        if let i = args.firstIndex(of: "-import-code"), args.indices.contains(i + 1) { incoming = try? ShareCode.decode(args[i + 1]); page = .importCode }
        if !data.onboardingComplete && page == nil { page = .onboarding }
        scheduler.onAction = { [weak self] action, day in
            guard let self = self else { return }; await self.handleNotification(action: action, day: day)
        }
        if !isolated { scheduler.register() }
    }
    func startServices() async {
        guard !started else { return }; started = true
        pendingMilestone = Milestone.next(periods: periods, shown: data.milestones)
        guard !isolated else { return }
        scheduler.register(); await refreshNotificationStatus()
        NSUbiquitousKeyValueStore.default.synchronize()
        detectCloudRestore()
        cloudObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.detectCloudRestore() }
        }
        purchasesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if case .verified(let t) = result { await self.refreshPurchases(); await t.finish() }
            }
        }
        autoCloseOpenPeriod()
        await refreshPurchases(); save(); checkPaste()
    }
    func setting<T>(_ key: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.data.settings[keyPath: key] }, set: { self.data.settings[keyPath: key] = $0; self.save() })
    }
    func reminder<T>(_ key: WritableKeyPath<Reminders, T>) -> Binding<T> {
        Binding(get: { self.data.reminders[keyPath: key] }, set: { self.data.reminders[keyPath: key] = $0; self.save() })
    }
    func log(on day: Day) -> DayLog { data.logs.first { $0.day == day } ?? DayLog(day: day) }
    func save(coreAction: Bool = false) {
        guard !loadFailed else { return }
        data.normalize(); data.updatedAt = Date()
        if !isolated {
            let previous = data.coreReviewProgress
            if coreAction { data.coreReviewProgress = .recording(previous) }
            do {
                try store.save(data)
                if coreAction { CoreReview.shared.record(data.coreReviewProgress) }
            } catch {
                data.coreReviewProgress = previous
                message = L.t("保存失败，请检查手机剩余空间。")
            }
            WidgetCenter.shared.reloadAllTimelines()
            schedulingTask?.cancel()
            let snapshot = data
            schedulingTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                await scheduler.reschedule(data: snapshot, now: Date())
            }
            if data.settings.cloudEnabled && premium {
                do { if try CloudBackup.write(data, today: today) { message = L.t("iCloud 空间有限，这次只备份了最近 5 年。本地记录完整保留。") } }
                catch { message = L.t("iCloud 备份未完成，本地记录已保留。你也可以导出备份文件。") }
            }
        }
        pendingMilestone = Milestone.next(periods: periods, shown: data.milestones)
    }
    func update(_ log: DayLog, sync: Bool = true) {
        guard log.day <= today, !loadFailed else { return }
        let changed = self.log(on: log.day) != log
        data.upsert(log)
        if log.flow?.isPeriod != true, data.settings.openPeriodStart == log.day { data.settings.openPeriodStart = nil }
        save(coreAction: changed)
        if sync && data.settings.healthEnabled && !isolated {
            let snapshot = data
            Task { do { try await health.write(log: log, data: snapshot) } catch { message = L.t("苹果健康同步未完成，本地记录已保存。") } }
        }
    }
    func beginPeriod(on day: Day) {
        guard day <= today else { return }
        let oldPrediction = prediction
        var log = log(on: day); log.flow = .medium
        data.settings.openPeriodStart = day; data.reminders.lateSnoozedUntil = nil
        if data.settings.predictionRestart != nil { data.settings.predictionRestart = min(data.settings.predictionRestart!, day) }
        update(log)
        let matched = oldPrediction.map { ($0.rangeStart...$0.rangeEnd).contains(day) } ?? false
        considerReview(matched: matched)
    }
    func endPeriod(on end: Day) {
        guard end <= today else { return }
        let start = data.settings.openPeriodStart ?? periods.last?.start ?? end
        guard end >= start, start.distance(to: end) <= 90 else { return }
        for n in 0...start.distance(to: end) {
            var log = log(on: start.adding(n)); if log.flow?.isPeriod != true { log.flow = .light }; data.upsert(log)
        }
        data.settings.openPeriodStart = nil; save()
        if data.settings.healthEnabled && !isolated {
            let snapshot = data
            Task { for l in snapshot.logs where l.day >= start && l.day <= end { try? await health.write(log: l, data: snapshot) } }
        }
    }
    func markPeriod(from a: Day, through b: Day, enabled: Bool) {
        let first = min(a, b), last = min(today, max(a, b))
        guard first <= last, first.distance(to: last) <= 366 else { return }
        for n in 0...first.distance(to: last) { var l = log(on: first.adding(n)); l.flow = enabled ? .medium : nil; l.periodLink = .automatic; data.upsert(l) }
        if let open = data.settings.openPeriodStart, (first...last).contains(open), !enabled { data.settings.openPeriodStart = nil }
        save()
        if data.settings.healthEnabled && !isolated {
            let snapshot = data
            Task { for n in 0...first.distance(to: last) { try? await health.write(log: self.log(on: first.adding(n)), data: snapshot) } }
        }
    }
    func confirmPeriod(_ period: Period, continuation: Bool) {
        var log = log(on: period.start); log.periodLink = continuation ? .continuation : .newPeriod; update(log)
    }
    func deleteLog(day: Day, deleteHealth: Bool) {
        data.logs.removeAll { $0.day == day }
        if data.settings.openPeriodStart == day { data.settings.openPeriodStart = nil }
        save()
        if deleteHealth && !isolated { Task { do { try await health.delete(day: day) } catch { message = L.t("未能删除苹果健康里的记录，本地记录已删除。") } } }
    }
    func autoCloseOpenPeriod() {
        guard let start = data.settings.openPeriodStart, start.distance(to: today) >= CycleCore.openPeriodLimit else { return }
        let length = prediction?.periodDays ?? data.settings.periodDays
        endPeriod(on: start.adding(max(1, min(14, length)) - 1))
    }
    func becomeActive() async {
        now = demo ? Demo.today.localDate() : Date()
        guard !isolated else { return }
        autoCloseOpenPeriod()
        checkPaste(); await refreshNotificationStatus(); await scheduler.reschedule(data: data, now: now)
        detectCloudRestore()
    }
    func refreshClock() {
        guard !demo else { return }
        let oldDay = today; now = Date()
        if today != oldDay {
            if selectedDay == oldDay { selectedDay = today }
            save()
        }
    }
    func checkPaste() {
        guard !ProcessInfo.processInfo.arguments.contains("-hide-paste-hint") else { return }
        let p = UIPasteboard.general
        if p.changeCount != lastPasteChange { pasteAvailable = p.hasStrings; lastPasteChange = p.changeCount }
    }
    func receiveCode(_ text: String) {
        do { incoming = try ShareCode.decode(text); importedFriendID = nil; page = .importCode }
        catch { message = L.t("没有识别到有效口令，请复制完整内容后再试。") }
    }
    func confirmIncoming() {
        guard let p = incoming else { return }
        do { importedFriendID = try ShareCode.importCode(p, into: &data, now: now); save() }
        catch DataError.ownCode { message = L.t("这是你自己的口令，可以把它发给朋友。") }
        catch { message = L.t("口令无法导入，请对方重新生成。") }
    }
    func makePayload(kind: ShareKind, name: Bool, duration: Bool, tips: Bool) throws -> ShareCode.Payload {
        guard let p = prediction else { throw DataError.noPrediction }
        var future = p.future
        if !duration { for i in future.indices { future[i].duration = nil } }
        return ShareCode.Payload(kind: kind, nickname: name && !data.settings.nickname.isEmpty ? String(data.settings.nickname.prefix(40)) : nil, generated: today, predictions: future, partnerTips: kind == .partner && tips, sourceID: data.settings.sourceID)
    }
    func dismissCard(_ id: String) { data.settings.dismissedCards.insert(id); save() }
    func showMilestone() {
        guard let m = pendingMilestone else { return }; data.milestones.insert(m); save(); pendingMilestone = m; page = .milestone
        considerReview(matched: false, milestone: m)
    }
    func considerReview(matched: Bool, milestone: Int? = nil) {
        guard let condition = ReviewGate.condition(periods: periods, matched: matched, milestone: milestone, requested: data.reviewConditions) else { return }
        if !isolated && message == nil { reviewCondition = condition }
    }
    func requestMilestoneReview(_ request: () -> Void) {
        guard let reviewCondition, CoreReview.shared.attempt(request) else { return }
        self.reviewCondition = nil
        data.reviewConditions.insert(reviewCondition)
        save()
    }

    func refreshNotificationStatus() async { notificationDenied = await scheduler.denied() }
    func askNotifications() async { guard !isolated else { return }; await scheduler.request(); await refreshNotificationStatus(); await scheduler.reschedule(data: data, now: Date()) }
    func handleNotification(action: String, day: Day) async {
        now = Date()
        switch action {
        case "PERIOD_STARTED": beginPeriod(on: today)
        case "PERIOD_NOT_YET":
            if let p = prediction {
                let key = p.nextStart.description
                data.reminders.lateResponses[key, default: 0] += 1
                data.reminders.lateSnoozedUntil = today.adding(3); save()
            }
        case "PILL_TAKEN": scheduler.cancelPill(on: day); var l = log(on: day); l.pillTaken = true; update(l)
        default: selectedDay = min(today, day)
        }
        if !isolated { await scheduler.reschedule(data: data, now: now) }
    }
    func detectCloudRestore() {
        guard data.logs.isEmpty, !isolated, !data.settings.dismissedCards.contains("cloud") else { return }
        do { cloudRestore = try CloudBackup.read() } catch { cloudRestore = nil }
    }
    func restoreCloud() {
        guard let backup = cloudRestore else { return }
        data.mergeBackup(backup); cloudRestore = nil; data.settings.dismissedCards.insert("cloud"); save()
    }
    func importHealth() async {
        guard !isolated else { healthStatus = L.t("演示模式不访问苹果健康。"); return }
        do {
            try await health.authorize(includeSex: data.settings.showSex || data.settings.purpose == .conceive)
            let logs = try await health.read(includeSex: data.settings.showSex || data.settings.purpose == .conceive)
            for l in logs { data.upsert(health.merge(existing: log(on: l.day), imported: l)) }
            data.settings.healthEnabled = true; save()
            healthStatus = L.f("已导入 %@ 天；健康读取权限由系统保护。", String(logs.count))
        } catch { healthStatus = L.t("未授权或同步失败，其余记录功能照常可用。") }
    }
    func loadProducts() async {
        guard !isolated else { return }
        do { products = try await Product.products(for: [proID, trialID]) }
        catch { message = L.t("暂时无法加载商品，请稍后重试。") }
    }
    func refreshPurchases() async {
        guard !isolated else { return }
        var pro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == proID { pro = true }
            if t.productID == trialID { data.entitlement.trialClaimedAt = min(data.entitlement.trialClaimedAt ?? t.originalPurchaseDate, t.originalPurchaseDate) }
        }
        data.entitlement.purchasedPro = pro; now = Date(); save()
    }
    func purchase(_ id: String) async {
        guard !purchasing, let product = products.first(where: { $0.id == id }), !isolated else { return }
        purchasing = true; defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result else { message = L.t("购买未通过验证，请稍后恢复购买。"); return }
                await t.finish(); await refreshPurchases()
            case .pending: message = L.t("购买正在等待确认。")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = L.t("购买未完成，请稍后重试。") }
    }
    func restorePurchases() async {
        guard !isolated else { return }
        do { try await AppStore.sync(); await refreshPurchases() } catch { message = L.t("恢复购买未完成，请稍后重试。") }
    }
    func deleteAll() {
        let entitlement = data.entitlement
        data = AppData(); data.entitlement = entitlement; data.onboardingComplete = true
        cloudRestore = nil; pendingMilestone = nil; selectedDay = today
        data.settings.dismissedCards.insert("cloud")
        if !isolated { CloudBackup.clear(); scheduler.cancelAll() }
        loadFailed = false; save()
    }
}
