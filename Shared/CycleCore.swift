import Foundation

struct Day: Hashable, Comparable, Codable, Identifiable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int
    var id: String { description }
    static var arithmeticCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year; self.month = month; self.day = day
    }
    init(date: Date = Date(), timeZone: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        year = c.component(.year, from: date)
        month = c.component(.month, from: date); day = c.component(.day, from: date)
    }
    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, string.count == 10,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1900...2200).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        let value = Day(y, m, d)
        guard let date = Self.arithmeticCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)),
              Self.arithmeticCalendar.component(.day, from: date) == d else { return nil }
        self = value
    }
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    private var arithmeticDate: Date {
        Self.arithmeticCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func localDate(hour: Int = 12, minute: Int = 0) -> Date {
        let c = Calendar(identifier: .gregorian)
        return c.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? arithmeticDate
    }
    func adding(_ days: Int) -> Day {
        Day(date: Self.arithmeticCalendar.date(byAdding: .day, value: days, to: arithmeticDate)!, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    func distance(to other: Day) -> Int {
        Self.arithmeticCalendar.dateComponents([.day], from: arithmeticDate, to: other.arithmeticDate).day ?? 0
    }
    func addingMonths(_ count: Int) -> Day {
        Day(date: Self.arithmeticCalendar.date(byAdding: .month, value: count, to: arithmeticDate)!, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    func addingYears(_ count: Int) -> Day {
        Day(date: Self.arithmeticCalendar.date(byAdding: .year, value: count, to: arithmeticDate)!, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    static func < (lhs: Day, rhs: Day) -> Bool { lhs.description < rhs.description }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(); let s = try c.decode(String.self)
        guard let day = Day(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid civil date") }
        self = day
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(description) }
}

enum Flow: String, Codable, CaseIterable { case none, spotting, light, medium, heavy
    var isPeriod: Bool { self == .light || self == .medium || self == .heavy }
    var title: String { L.t(["none": "无", "spotting": "点滴", "light": "少", "medium": "中", "heavy": "多"][rawValue] ?? "无") }
}
enum OvulationTest: String, Codable, CaseIterable { case negative, faint, positive
    var title: String { L.t(self == .negative ? "阴性" : self == .faint ? "弱阳" : "强阳") }
}
enum PregnancyTest: String, Codable, CaseIterable { case negative, positive
    var title: String { L.t(self == .negative ? "阴性" : "阳性") }
}
enum Sex: String, Codable, CaseIterable { case none, protected, unprotected
    var title: String { L.t(self == .none ? "无" : self == .protected ? "有保护" : "无保护") }
}
enum PeriodLink: String, Codable { case automatic, newPeriod, continuation }
enum Discharge: String, Codable, CaseIterable { case dry, sticky, creamy, watery, eggWhite
    var title: String { L.t(["dry": "干燥", "sticky": "黏稠", "creamy": "乳状", "watery": "水状", "eggWhite": "蛋清状"][rawValue] ?? "干燥") }
}
enum Purpose: String, Codable, CaseIterable { case record, conceive, pill
    var title: String { L.t(self == .record ? "只是记录" : self == .conceive ? "想知道易孕期（备孕）" : "吃避孕药要提醒") }
}
enum PauseReason: String, Codable, CaseIterable { case pregnancy, postpartum, breastfeeding, other
    var title: String { L.t(self == .pregnancy ? "怀孕" : self == .postpartum ? "产后" : self == .breastfeeding ? "哺乳" : "其他") }
}

struct DayLog: Codable, Equatable, Identifiable {
    var day: Day
    var flow: Flow?
    var symptoms: Set<String> = []
    var moods: Set<String> = []
    var discharge: Discharge?
    var bbt: Int?
    var ovulationTest: OvulationTest?
    var pregnancyTest: PregnancyTest?
    var sex: Sex?
    var pillTaken: Bool?
    var note = ""
    var periodLink: PeriodLink = .automatic
    var id: Day { day }
    var hasRecord: Bool { flow != nil || !symptoms.isEmpty || !moods.isEmpty || discharge != nil || bbt != nil || ovulationTest != nil || pregnancyTest != nil || sex != nil || pillTaken != nil || !note.isEmpty }
    init(day: Day) { self.day = day }
    enum CodingKeys: String, CodingKey { case day, flow, symptoms, moods, discharge, bbt, ovulationTest, pregnancyTest, sex, pillTaken, note, periodLink }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Day.self, forKey: .day)
        flow = try c.decodeIfPresent(Flow.self, forKey: .flow)
        symptoms = try c.decodeIfPresent(Set<String>.self, forKey: .symptoms) ?? []
        moods = try c.decodeIfPresent(Set<String>.self, forKey: .moods) ?? []
        discharge = try c.decodeIfPresent(Discharge.self, forKey: .discharge)
        bbt = try c.decodeIfPresent(Int.self, forKey: .bbt)
        ovulationTest = try c.decodeIfPresent(OvulationTest.self, forKey: .ovulationTest)
        pregnancyTest = try c.decodeIfPresent(PregnancyTest.self, forKey: .pregnancyTest)
        sex = try c.decodeIfPresent(Sex.self, forKey: .sex)
        pillTaken = try c.decodeIfPresent(Bool.self, forKey: .pillTaken)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        periodLink = try c.decodeIfPresent(PeriodLink.self, forKey: .periodLink) ?? .automatic
    }
}

enum RecordOptions {
    static let symptoms = ["abdominalCramps", "headache", "lowerBackPain", "breastPain", "bloating", "acne", "fatigue", "nausea", "sleepChanges", "appetiteChanges", "moodChanges"]
    static let moods = ["calm", "happy", "low", "irritable", "anxious", "sensitive"]
    static func title(_ key: String) -> String {
        let names = ["abdominalCramps": "腹痛", "headache": "头痛", "lowerBackPain": "腰酸", "breastPain": "胸胀", "bloating": "胀气", "acne": "长痘", "fatigue": "疲倦", "nausea": "恶心", "sleepChanges": "失眠", "appetiteChanges": "想吃东西", "moodChanges": "情绪波动", "calm": "平静", "happy": "开心", "low": "低落", "irritable": "烦躁", "anxious": "焦虑", "sensitive": "敏感"]
        return names[key].map { L.t($0) } ?? key
    }
}

struct Period: Equatable, Identifiable {
    var start: Day
    var end: Day
    var needsConfirmation = false
    var id: Day { start }
    var duration: Int { start.distance(to: end) + 1 }
}
struct Forecast: Codable, Equatable, Identifiable {
    var start: Day
    var rangeStart: Day
    var rangeEnd: Day
    var duration: Int?
    var id: Day { start }
}
enum Regularity: String, Codable { case regular, variable, irregular
    var title: String { L.t(self == .regular ? "规律" : self == .variable ? "有些波动" : "不规律") }
}
enum CyclePhase { case period, fertile, ovulation, other, late }
struct Prediction: Equatable {
    var nextStart: Day
    var rangeStart: Day
    var rangeEnd: Day
    var periodDays: Int
    var cycleDays: Int
    var ovulation: Day
    var fertileStart: Day
    var fertileEnd: Day
    var future: [Forecast]
    var regularity: Regularity
    var standardDeviation: Double
    var lateDays: Int
    var matchedLastPeriod: Bool
    var isLate: Bool { lateDays > 0 }
}
enum SymptomStage: String, CaseIterable { case before, during, other
    var title: String { L.t(self == .before ? "经期前 3 天" : self == .during ? "经期中" : "其他") }
}
struct SymptomCount: Identifiable, Equatable { var key: String; var count: Int; var id: String { key } }
struct CycleStatistics {
    var lengths: [Int]
    var averageCycle: Double?
    var averagePeriod: Double?
    var shortest: Int?
    var longest: Int?
    var regularity: Regularity
    var symptoms: [SymptomStage: [SymptomCount]]
}

enum CycleCore {
    static let openPeriodLimit = 15
    static func periods(_ logs: [DayLog]) -> [Period] {
        let days = logs.filter { $0.flow?.isPeriod == true }.sorted { $0.day < $1.day }
        var result: [Period] = []
        for log in days {
            if let last = result.last, log.day == last.end { continue }
            if let last = result.last, log.periodLink != .newPeriod,
               (last.end.distance(to: log.day) <= 2 || log.periodLink == .continuation) {
                result[result.count - 1].end = log.day
            } else {
                let close = result.last.map { $0.start.distance(to: log.day) < 15 } ?? false
                result.append(Period(start: log.day, end: log.day, needsConfirmation: close && log.periodLink == .automatic))
            }
        }
        return result
    }
    static func lengths(_ periods: [Period]) -> [Int] {
        guard periods.count > 1 else { return [] }
        return zip(periods, periods.dropFirst()).map { $0.start.distance(to: $1.start) }
    }
    static func validLengths(_ periods: [Period]) -> [Int] { lengths(periods).filter { (15...90).contains($0) } }
    static func deviation(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        return sqrt(values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count))
    }
    static func regularity(_ sd: Double) -> Regularity { sd <= 3 ? .regular : sd <= 7 ? .variable : .irregular }
    static func estimate(_ periods: [Period], settings: Settings) -> (length: Int, spread: Int, sd: Double) {
        let values = Array(validLengths(periods).suffix(6))
        let sd = deviation(values)
        guard values.count >= 2 else { return (settings.cycleDays, 3, sd) }
        let weighted = values.enumerated().reduce(0.0) { $0 + Double($1.element * (7 - values.count + $1.offset)) }
        let denominator = (0..<values.count).reduce(0) { $0 + 7 - values.count + $1 }
        return (Int((weighted / Double(denominator)).rounded()), max(2, Int(sd.rounded())), sd)
    }
    static func predict(logs: [DayLog], settings: Settings, today: Day) -> Prediction? {
        guard settings.pauseReason == nil, !settings.recordOnly else { return nil }
        let history = periods(logs.filter { $0.day <= today && (settings.predictionRestart == nil || $0.day >= settings.predictionRestart!) })
        guard let latest = history.last else { return nil }
        let estimate = estimate(history, settings: settings)
        let completed = history.filter { $0.start != settings.openPeriodStart }.suffix(6).map(\.duration).sorted()
        let duration: Int
        if completed.isEmpty { duration = settings.periodDays }
        else if completed.count % 2 == 0 { duration = Int((Double(completed[completed.count / 2 - 1] + completed[completed.count / 2]) / 2).rounded()) }
        else { duration = completed[completed.count / 2] }
        let next = latest.start.adding(estimate.length)
        let rangeStart = next.adding(-estimate.spread), rangeEnd = next.adding(estimate.spread)
        var ovulation = next.adding(-14)
        if settings.purpose == .conceive, let positive = logs.filter({ $0.day >= latest.start && $0.day <= today && $0.ovulationTest == .positive }).max(by: { $0.day < $1.day }) { ovulation = positive.day.adding(1) }
        let future = (1...3).map { index -> Forecast in
            let start = latest.start.adding(estimate.length * index)
            return Forecast(start: start, rangeStart: start.adding(-estimate.spread), rangeEnd: start.adding(estimate.spread), duration: max(1, min(14, duration)))
        }
        var matched = false
        if history.count > 1 {
            let old = Array(history.dropLast()); let e = self.estimate(old, settings: settings)
            let expected = old.last!.start.adding(e.length)
            matched = (expected.adding(-e.spread)...expected.adding(e.spread)).contains(latest.start)
        }
        return Prediction(nextStart: next, rangeStart: rangeStart, rangeEnd: rangeEnd, periodDays: max(1, min(14, duration)), cycleDays: estimate.length, ovulation: ovulation, fertileStart: ovulation.adding(-5), fertileEnd: ovulation.adding(1), future: future, regularity: regularity(estimate.sd), standardDeviation: estimate.sd, lateDays: max(0, rangeEnd.distance(to: today)), matchedLastPeriod: matched)
    }
    static func cycleDay(logs: [DayLog], on day: Day) -> Int? {
        guard let start = periods(logs).last(where: { $0.start <= day })?.start else { return nil }
        return start.distance(to: day) + 1
    }
    static func phase(logs: [DayLog], settings: Settings, on day: Day, prediction: Prediction?) -> CyclePhase {
        if logs.contains(where: { $0.day == day && $0.flow?.isPeriod == true }) { return .period }
        if let start = settings.openPeriodStart, start <= day, start.distance(to: day) < CycleCore.openPeriodLimit { return .period }
        guard let p = prediction else { return .other }
        if day > p.rangeEnd { return .late }
        if day == p.ovulation { return .ovulation }
        if (p.fertileStart...p.fertileEnd).contains(day) { return .fertile }
        return .other
    }
    static func statistics(logs: [DayLog]) -> CycleStatistics {
        let p = periods(logs); let observed = lengths(p)
        var grouped: [SymptomStage: [String: Int]] = [:]
        for log in logs {
            let stage: SymptomStage
            if p.contains(where: { ($0.start...$0.end).contains(log.day) }) { stage = .during }
            else if p.contains(where: { ($0.start.adding(-3)..<$0.start).contains(log.day) }) { stage = .before }
            else { stage = .other }
            for key in log.symptoms { grouped[stage, default: [:]][key, default: 0] += 1 }
        }
        var symptoms: [SymptomStage: [SymptomCount]] = [:]
        for (stage, counts) in grouped {
            var list: [SymptomCount] = []
            for (key, count) in counts { list.append(SymptomCount(key: key, count: count)) }
            list.sort { (a: SymptomCount, b: SymptomCount) -> Bool in
                if a.count == b.count { return a.key < b.key }
                return a.count > b.count
            }
            symptoms[stage] = list
        }
        var averageCycle: Double? = nil
        if !observed.isEmpty {
            let total: Int = observed.reduce(0, +)
            averageCycle = Double(total) / Double(observed.count)
        }
        var averagePeriod: Double? = nil
        if !p.isEmpty {
            let durations: [Int] = p.map { $0.duration }
            let total: Int = durations.reduce(0, +)
            averagePeriod = Double(total) / Double(p.count)
        }
        let reg: Regularity = regularity(deviation(observed))
        return CycleStatistics(lengths: observed, averageCycle: averageCycle, averagePeriod: averagePeriod, shortest: observed.min(), longest: observed.max(), regularity: reg, symptoms: symptoms)
    }
    static func temperatureRaised(_ logs: [DayLog], today: Day) -> Bool {
        let map = Dictionary(logs.map { ($0.day, $0.bbt) }, uniquingKeysWith: { _, b in b })
        let recent = (0..<3).compactMap { map[today.adding(-$0)] ?? nil }
        let baseline = (3..<9).compactMap { map[today.adding(-$0)] ?? nil }
        guard recent.count == 3, baseline.count >= 3 else { return false }
        let mean = Double(baseline.reduce(0, +)) / Double(baseline.count)
        return recent.allSatisfy { Double($0) >= mean + 20 }
    }
}
