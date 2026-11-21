import Foundation
import HealthKit
import CryptoKit

actor HealthKitSync {
    private let store = HKHealthStore()
    private let symptomTypes: [(String, HKCategoryTypeIdentifier)] = [
        ("abdominalCramps", .abdominalCramps), ("headache", .headache), ("bloating", .bloating),
        ("acne", .acne), ("breastPain", .breastPain), ("fatigue", .fatigue), ("nausea", .nausea),
        ("moodChanges", .moodChanges), ("sleepChanges", .sleepChanges), ("lowerBackPain", .lowerBackPain), ("appetiteChanges", .appetiteChanges)
    ]
    private var previousWrite: Task<Void, Error>?
    private func types(includeSex: Bool) -> [HKSampleType] {
        var identifiers: [HKCategoryTypeIdentifier] = [.menstrualFlow, .intermenstrualBleeding, .ovulationTestResult, .pregnancyTestResult, .cervicalMucusQuality, .contraceptive]
        identifiers += symptomTypes.map { $0.1 }
        if includeSex { identifiers.append(.sexualActivity) }
        var types: [HKSampleType] = identifiers.compactMap { HKObjectType.categoryType(forIdentifier: $0) }
        if let t = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature) { types.append(t) }
        return types
    }
    func authorize(includeSex: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw DataError.corrupt }
        let values = types(includeSex: includeSex)
        try await store.requestAuthorization(toShare: Set(values), read: Set(values.map { $0 as HKObjectType }))
    }
    func write(log: DayLog, data: AppData) async throws {
        let previous = previousWrite
        let task = Task {
            _ = try? await previous?.value
            try await self.performWrite(log: log, data: data)
        }
        previousWrite = task
        try await task.value
    }
    private func externalID(day: Day, type: HKSampleType) -> String {
        SHA256.hash(data: Data((day.description + ":" + type.identifier).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func performWrite(log: DayLog, data: AppData) async throws {
        let includeSex = data.settings.showSex || data.settings.purpose == .conceive
        let start = log.day.localDate(), end = start.addingTimeInterval(60)
        var samples: [HKSample] = []
        func metadata(_ type: HKSampleType) -> [String: Any] {
            [HKMetadataKeyExternalUUID: externalID(day: log.day, type: type), "PeriodLogOwner": "periodlog", "PeriodLogDay": log.day.description]
        }
        func category(_ id: HKCategoryTypeIdentifier, _ value: Int, extra: [String: Any] = [:]) {
            guard let type = HKObjectType.categoryType(forIdentifier: id), store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            var meta = metadata(type); meta.merge(extra) { _, new in new }
            samples.append(HKCategorySample(type: type, value: value, start: start, end: end, metadata: meta))
        }
        if let flow = log.flow {
            switch flow {
            case .spotting: category(.intermenstrualBleeding, HKCategoryValue.notApplicable.rawValue)
            case .none: category(.menstrualFlow, HKCategoryValueMenstrualFlow.none.rawValue)
            case .light, .medium, .heavy:
                let value = flow == .light ? HKCategoryValueMenstrualFlow.light : flow == .medium ? .medium : .heavy
                category(.menstrualFlow, value.rawValue, extra: [HKMetadataKeyMenstrualCycleStart: CycleCore.periods(data.logs).contains { $0.start == log.day }])
            }
        }
        if let bbt = log.bbt, let type = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature), store.authorizationStatus(for: type) == .sharingAuthorized {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: Double(bbt) / 100), start: start, end: end, metadata: metadata(type)))
        }
        if let test = log.ovulationTest {
            let value = test == .positive ? HKCategoryValueOvulationTestResult.luteinizingHormoneSurge : test == .negative ? .negative : .indeterminate
            category(.ovulationTestResult, value.rawValue, extra: ["PeriodLogTest": test.rawValue])
        }
        if let test = log.pregnancyTest { category(.pregnancyTestResult, test == .positive ? HKCategoryValuePregnancyTestResult.positive.rawValue : HKCategoryValuePregnancyTestResult.negative.rawValue) }
        if includeSex, let sex = log.sex, sex != .none { category(.sexualActivity, HKCategoryValue.notApplicable.rawValue, extra: [HKMetadataKeySexualActivityProtectionUsed: sex == .protected]) }
        if let discharge = log.discharge {
            let values: [Discharge: HKCategoryValueCervicalMucusQuality] = [.dry: .dry, .sticky: .sticky, .creamy: .creamy, .watery: .watery, .eggWhite: .eggWhite]
            category(.cervicalMucusQuality, values[discharge]!.rawValue)
        }
        if log.pillTaken == true { category(.contraceptive, HKCategoryValueContraceptive.oral.rawValue) }
        for (key, id) in symptomTypes where log.symptoms.contains(key) {
            let value: Int
            if key == "sleepChanges" || key == "moodChanges" { value = HKCategoryValuePresence.present.rawValue }
            else if key == "appetiteChanges" { value = HKCategoryValueAppetiteChanges.increased.rawValue }
            else { value = HKCategoryValueSeverity.mild.rawValue }
            category(id, value)
        }
        for type in types(includeSex: includeSex) where store.authorizationStatus(for: type) == .sharingAuthorized {
            let id = externalID(day: log.day, type: type)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id]), HKQuery.predicateForObjects(from: HKSource.default())])
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
        if !samples.isEmpty { try await store.save(samples) }
    }
    func delete(day: Day) async throws {
        let previous = previousWrite
        let task = Task {
            _ = try? await previous?.value
            try await self.performDelete(day: day)
        }
        previousWrite = task
        try await task.value
    }
    private func performDelete(day: Day) async throws {
        for type in types(includeSex: true) where store.authorizationStatus(for: type) == .sharingAuthorized {
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [externalID(day: day, type: type)]), HKQuery.predicateForObjects(from: HKSource.default())])
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
    private func query(_ type: HKSampleType) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(q)
        }
    }
    func read(includeSex: Bool) async throws -> [DayLog] {
        var days: [Day: DayLog] = [:]
        for type in types(includeSex: includeSex) {
            for sample in try await query(type) {
                let day = (sample.metadata?["PeriodLogDay"] as? String).flatMap(Day.init) ?? Day(date: sample.startDate)
                guard day <= Day() else { continue }
                var log = days[day] ?? DayLog(day: day)
                if let quantity = sample as? HKQuantitySample { log.bbt = Int((quantity.quantity.doubleValue(for: .degreeCelsius()) * 100).rounded()) }
                if let c = sample as? HKCategorySample {
                    switch type.identifier {
                    case HKCategoryTypeIdentifier.menstrualFlow.rawValue:
                        if c.value == HKCategoryValueMenstrualFlow.light.rawValue { log.flow = .light }
                        else if c.value == HKCategoryValueMenstrualFlow.medium.rawValue { log.flow = .medium }
                        else if c.value == HKCategoryValueMenstrualFlow.heavy.rawValue { log.flow = .heavy }
                        else if c.value == HKCategoryValueMenstrualFlow.none.rawValue { log.flow = Flow.none }
                    case HKCategoryTypeIdentifier.intermenstrualBleeding.rawValue: if log.flow?.isPeriod != true { log.flow = .spotting }
                    case HKCategoryTypeIdentifier.ovulationTestResult.rawValue:
                        log.ovulationTest = (c.metadata?["PeriodLogTest"] as? String).flatMap(OvulationTest.init(rawValue:)) ?? (c.value == HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue ? .positive : c.value == HKCategoryValueOvulationTestResult.negative.rawValue ? .negative : .faint)
                    case HKCategoryTypeIdentifier.pregnancyTestResult.rawValue:
                        if c.value == HKCategoryValuePregnancyTestResult.positive.rawValue { log.pregnancyTest = .positive }
                        else if c.value == HKCategoryValuePregnancyTestResult.negative.rawValue { log.pregnancyTest = .negative }
                    case HKCategoryTypeIdentifier.sexualActivity.rawValue: log.sex = (c.metadata?[HKMetadataKeySexualActivityProtectionUsed] as? Bool) == true ? .protected : .unprotected
                    case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue:
                        let pairs: [(HKCategoryValueCervicalMucusQuality, Discharge)] = [(.dry, .dry), (.sticky, .sticky), (.creamy, .creamy), (.watery, .watery), (.eggWhite, .eggWhite)]
                        log.discharge = pairs.first { $0.0.rawValue == c.value }?.1
                    case HKCategoryTypeIdentifier.contraceptive.rawValue: if c.value == HKCategoryValueContraceptive.oral.rawValue { log.pillTaken = true }
                    default:
                        if let key = symptomTypes.first(where: { $0.1.rawValue == type.identifier })?.0 {
                            let present: Bool
                            if key == "appetiteChanges" { present = c.value != HKCategoryValueAppetiteChanges.noChange.rawValue }
                            else if key == "moodChanges" || key == "sleepChanges" { present = c.value == HKCategoryValuePresence.present.rawValue }
                            else { present = c.value != HKCategoryValueSeverity.notPresent.rawValue }
                            if present { log.symptoms.insert(key) } else { log.symptoms.remove(key) }
                        }
                    }
                }
                days[day] = log
            }
        }
        return days.values.filter(\.hasRecord).sorted { $0.day < $1.day }
    }
    nonisolated func merge(existing: DayLog, imported: DayLog) -> DayLog {
        var result = existing
        if result.flow == nil { result.flow = imported.flow }
        result.symptoms.formUnion(imported.symptoms); result.moods.formUnion(imported.moods)
        if result.bbt == nil { result.bbt = imported.bbt }
        if result.discharge == nil { result.discharge = imported.discharge }
        if result.ovulationTest == nil { result.ovulationTest = imported.ovulationTest }
        if result.pregnancyTest == nil { result.pregnancyTest = imported.pregnancyTest }
        if result.sex == nil { result.sex = imported.sex }
        if result.pillTaken == nil { result.pillTaken = imported.pillTaken }
        return result
    }
}
