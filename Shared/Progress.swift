import Foundation

enum Milestone {
    static let thresholds = [3, 6, 12, 24]
    static func consecutiveCycles(_ periods: [Period]) -> Int {
        guard !periods.isEmpty else { return 0 }
        var count = 1
        for length in CycleCore.lengths(periods).reversed() {
            guard (15...90).contains(length) else { break }; count += 1
        }
        return count
    }
    static func next(periods: [Period], shown: Set<Int>) -> Int? {
        let count = consecutiveCycles(periods)
        return thresholds.first { count >= $0 && !shown.contains($0) }
    }
}
enum ReviewGate {
    static func condition(periods: [Period], matched: Bool, milestone: Int?, requested: Set<String>) -> String? {
        if periods.count == 2 && matched && !requested.contains("second-match") { return "second-match" }
        if milestone != nil && !requested.contains("first-milestone") { return "first-milestone" }
        return nil
    }
}
