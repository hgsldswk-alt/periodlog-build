import Foundation

struct Settings: Codable, Equatable {
    var purpose: Purpose = .record
    var cycleDays = 28
    var periodDays = 5
    var irregular = false
    var pauseReason: PauseReason?
    var recordOnly = false
    var showSex = false
    var discreetNotifications = true
    var discreetWidget = true
    var faceLock = false
    var healthEnabled = false
    var cloudEnabled = false
    var nickname = ""
    var customSymptoms: [String] = []
    var openPeriodStart: Day?
    var predictionRestart: Day?
    var sourceID = UUID()
    var dismissedCards: Set<String> = []
    init() {}
    enum CodingKeys: String, CodingKey { case purpose, cycleDays, periodDays, irregular, pauseReason, recordOnly, showSex, discreetNotifications, discreetWidget, faceLock, healthEnabled, cloudEnabled, nickname, customSymptoms, openPeriodStart, predictionRestart, sourceID, dismissedCards }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        purpose = try c.decodeIfPresent(Purpose.self, forKey: .purpose) ?? .record
        cycleDays = max(15, min(90, try c.decodeIfPresent(Int.self, forKey: .cycleDays) ?? 28))
        periodDays = max(1, min(14, try c.decodeIfPresent(Int.self, forKey: .periodDays) ?? 5))
        irregular = try c.decodeIfPresent(Bool.self, forKey: .irregular) ?? false
        pauseReason = try c.decodeIfPresent(PauseReason.self, forKey: .pauseReason)
        recordOnly = try c.decodeIfPresent(Bool.self, forKey: .recordOnly) ?? false
        showSex = try c.decodeIfPresent(Bool.self, forKey: .showSex) ?? false
        discreetNotifications = try c.decodeIfPresent(Bool.self, forKey: .discreetNotifications) ?? true
        discreetWidget = try c.decodeIfPresent(Bool.self, forKey: .discreetWidget) ?? true
        faceLock = try c.decodeIfPresent(Bool.self, forKey: .faceLock) ?? false
        healthEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthEnabled) ?? false
        cloudEnabled = try c.decodeIfPresent(Bool.self, forKey: .cloudEnabled) ?? false
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        customSymptoms = try c.decodeIfPresent([String].self, forKey: .customSymptoms) ?? []
        openPeriodStart = try c.decodeIfPresent(Day.self, forKey: .openPeriodStart)
        predictionRestart = try c.decodeIfPresent(Day.self, forKey: .predictionRestart)
        sourceID = try c.decodeIfPresent(UUID.self, forKey: .sourceID) ?? UUID()
        dismissedCards = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedCards) ?? []
    }
}
enum PillMode: String, Codable, CaseIterable { case days21and7, days24and4, days28, continuous
    var title: String { L.t(self == .days21and7 ? "21 天 + 7 天间隔" : self == .days24and4 ? "24 天 + 4 天间隔" : self == .days28 ? "28 天连续" : "不间断") }
    func isActive(offset: Int) -> Bool {
        guard offset >= 0 else { return false }
        switch self { case .days21and7: return offset % 28 < 21; case .days24and4: return offset % 28 < 24; case .days28, .continuous: return true }
    }
}
struct Reminders: Codable, Equatable {
    var nextPeriod = true
    var daysBefore = 2
    var late = true
    var fertile = false
    var daily = false
    var dailyHour = 20
    var dailyMinute = 0
    var pill = false
    var pillHour = 21
    var pillMinute = 0
    var pillMode: PillMode = .continuous
    var pillStart = Day()
    var lateResponses: [String: Int] = [:]
    var lateSnoozedUntil: Day?
    init() {}
    enum CodingKeys: String, CodingKey { case nextPeriod, daysBefore, late, fertile, daily, dailyHour, dailyMinute, pill, pillHour, pillMinute, pillMode, pillStart, lateResponses, lateSnoozedUntil }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        nextPeriod = try c.decodeIfPresent(Bool.self, forKey: .nextPeriod) ?? true
        daysBefore = max(0, min(7, try c.decodeIfPresent(Int.self, forKey: .daysBefore) ?? 2))
        late = try c.decodeIfPresent(Bool.self, forKey: .late) ?? true
        fertile = try c.decodeIfPresent(Bool.self, forKey: .fertile) ?? false
        daily = try c.decodeIfPresent(Bool.self, forKey: .daily) ?? false
        dailyHour = max(0, min(23, try c.decodeIfPresent(Int.self, forKey: .dailyHour) ?? 20))
        dailyMinute = max(0, min(59, try c.decodeIfPresent(Int.self, forKey: .dailyMinute) ?? 0))
        pill = try c.decodeIfPresent(Bool.self, forKey: .pill) ?? false
        pillHour = max(0, min(23, try c.decodeIfPresent(Int.self, forKey: .pillHour) ?? 21))
        pillMinute = max(0, min(59, try c.decodeIfPresent(Int.self, forKey: .pillMinute) ?? 0))
        pillMode = try c.decodeIfPresent(PillMode.self, forKey: .pillMode) ?? .continuous
        pillStart = try c.decodeIfPresent(Day.self, forKey: .pillStart) ?? Day()
        lateResponses = try c.decodeIfPresent([String: Int].self, forKey: .lateResponses) ?? [:]
        lateSnoozedUntil = try c.decodeIfPresent(Day.self, forKey: .lateSnoozedUntil)
    }
}
struct AppData: Codable, Equatable {
    var version = 1
    var logs: [DayLog] = []
    var settings = Settings()
    var friends: [Friend] = []
    var reminders = Reminders()
    var milestones: Set<Int> = []
    var reviewConditions: Set<String> = []
    var coreReviewProgress: CoreReviewProgress?
    var onboardingComplete = false
    var entitlement = Entitlement()
    var expiryNoticeShown = false
    var updatedAt = Date()
    init() {}
    enum CodingKeys: String, CodingKey { case version, logs, settings, friends, reminders, milestones, reviewConditions, onboardingComplete, entitlement, expiryNoticeShown, updatedAt, coreReviewProgress }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else { throw DataError.unsupportedVersion }
        logs = try c.decodeIfPresent([DayLog].self, forKey: .logs) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        friends = try c.decodeIfPresent([Friend].self, forKey: .friends) ?? []
        reminders = try c.decodeIfPresent(Reminders.self, forKey: .reminders) ?? Reminders()
        milestones = try c.decodeIfPresent(Set<Int>.self, forKey: .milestones) ?? []
        reviewConditions = try c.decodeIfPresent(Set<String>.self, forKey: .reviewConditions) ?? []
        coreReviewProgress = try? c.decode(CoreReviewProgress.self, forKey: .coreReviewProgress)
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        entitlement = try c.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? Entitlement()
        expiryNoticeShown = try c.decodeIfPresent(Bool.self, forKey: .expiryNoticeShown) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        normalize()
    }
    mutating func normalize() {
        logs = Array(Dictionary(logs.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b }).values).sorted { $0.day < $1.day }
        logs = logs.filter(\.hasRecord)
    }
    mutating func upsert(_ log: DayLog) {
        logs.removeAll { $0.day == log.day }
        if log.hasRecord { logs.append(log) }; logs.sort { $0.day < $1.day }
    }
    mutating func mergeBackup(_ backup: AppData) {
        let wasEmpty = logs.isEmpty
        if wasEmpty {
            let local = settings
            settings = backup.settings
            settings.sourceID = local.sourceID
            settings.faceLock = local.faceLock
            settings.healthEnabled = local.healthEnabled
            settings.cloudEnabled = local.cloudEnabled
            reminders = backup.reminders
        }
        for log in backup.logs { upsert(log) }
        for friend in backup.friends {
            if let i = friends.firstIndex(where: { $0.sourceID == friend.sourceID }) { friends[i] = friend }
            else { friends.append(friend) }
        }
        entitlement.firstOpen = min(entitlement.firstOpen, backup.entitlement.firstOpen)
        if let claim = backup.entitlement.trialClaimedAt { entitlement.trialClaimedAt = min(entitlement.trialClaimedAt ?? claim, claim) }
        milestones.formUnion(backup.milestones)
        reviewConditions.formUnion(backup.reviewConditions)
        expiryNoticeShown = expiryNoticeShown || backup.expiryNoticeShown
        if !logs.isEmpty { onboardingComplete = true }
    }
}
enum DataError: Error { case unsupportedVersion, tooLarge, corrupt, wrongPassword, ownCode, noPrediction }

struct Store {
    let url: URL
    init(url: URL? = nil) {
        if let url = url { self.url = url; return }
        let group = Bundle.main.object(forInfoDictionaryKey: "PeriodLogAppGroup") as? String ?? "group.com.hgsldswk.periodlog"
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = directory.appendingPathComponent("periodlog.json")
    }
    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= Zlib.maxJSONLength else { throw DataError.tooLarge }
        return try JSONDecoder().decode(AppData.self, from: bytes)
    }
    func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(data)
        guard bytes.count <= Zlib.maxJSONLength else { throw DataError.tooLarge }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
