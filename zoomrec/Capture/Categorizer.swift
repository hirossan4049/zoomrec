import Foundation

enum Categorizer {
    static func resolveCategory(
        for date: Date,
        in categories: inout [DayPeriodCategory],
        calendar: Calendar = .current
    ) -> DayPeriodCategory {
        if let slot = periodSlot(at: date, calendar: calendar) {
            let weekday = ourWeekday(from: date, calendar: calendar)
            if let existing = categories.first(where: { $0.weekday == weekday && $0.period == slot.period }) {
                return existing
            }
            let new = DayPeriodCategory(id: UUID(), weekday: weekday, period: slot.period)
            categories.append(new)
            return new
        }
        if let existing = categories.first(where: { $0.isUncategorized }) {
            return existing
        }
        let new = DayPeriodCategory(id: UUID(), weekday: 0, period: 0)
        categories.append(new)
        return new
    }
}
