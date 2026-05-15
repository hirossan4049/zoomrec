import Foundation

struct Screenshot: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    var capturedAt: Date
    var categoryId: UUID
}

struct Library: Codable {
    var categories: [DayPeriodCategory]
    var screenshots: [Screenshot]
}
