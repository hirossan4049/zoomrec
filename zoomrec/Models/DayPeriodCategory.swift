import Foundation

struct DayPeriodCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var weekday: Int
    var period: Int
    var customName: String?

    var isUncategorized: Bool { weekday == 0 || period == 0 }

    var displayName: String {
        if let name = customName, !name.isEmpty { return name }
        if isUncategorized { return "未分類" }
        return "\(weekdayKanji[weekday] ?? "?")曜\(period)限"
    }

    var sortKey: Int { isUncategorized ? Int.max : weekday * 10 + period }
}
