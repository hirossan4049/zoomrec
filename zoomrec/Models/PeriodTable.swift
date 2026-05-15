import Foundation

struct PeriodSlot: Hashable {
    let period: Int
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }
}

let periodTable: [PeriodSlot] = [
    PeriodSlot(period: 1, startHour: 9,  startMinute: 0,  endHour: 10, endMinute: 30),
    PeriodSlot(period: 2, startHour: 10, startMinute: 45, endHour: 12, endMinute: 15),
    PeriodSlot(period: 3, startHour: 13, startMinute: 15, endHour: 14, endMinute: 45),
    PeriodSlot(period: 4, startHour: 15, startMinute: 0,  endHour: 16, endMinute: 30),
    PeriodSlot(period: 5, startHour: 16, startMinute: 45, endHour: 18, endMinute: 15),
    PeriodSlot(period: 6, startHour: 18, startMinute: 25, endHour: 19, endMinute: 55),
    PeriodSlot(period: 7, startHour: 20, startMinute: 5,  endHour: 21, endMinute: 35),
]

func periodSlot(at date: Date, calendar: Calendar = .current) -> PeriodSlot? {
    let comps = calendar.dateComponents([.hour, .minute], from: date)
    let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    return periodTable.first { slot in
        minutes >= slot.startMinutes && minutes < slot.endMinutes
    }
}
