import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    static func day(_ day: Day, weekday: Bool = false) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(weekday ? "MMM d EEE" : "MMM d")
        return f.string(from: day.localDate())
    }
    static func range(_ start: Day, _ end: Day) -> String { day(start) + " – " + day(end) }
    static var disclaimer: String { t("预测基于你的记录，仅供参考，也不能用于避孕。") }
}
