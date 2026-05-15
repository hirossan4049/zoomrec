import Foundation

let weekdayKanji: [Int: String] = [
    1: "月", 2: "火", 3: "水", 4: "木", 5: "金", 6: "土", 7: "日"
]

func ourWeekday(from date: Date, calendar: Calendar = .current) -> Int {
    let apple = calendar.component(.weekday, from: date)
    return apple == 1 ? 7 : apple - 1
}
