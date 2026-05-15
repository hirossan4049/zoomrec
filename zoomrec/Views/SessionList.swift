import SwiftUI

struct SessionList: View {
    @EnvironmentObject var store: LibraryStore
    let categoryId: UUID?
    @Binding var selection: Date?

    var body: some View {
        List(selection: $selection) {
            ForEach(dateGroups, id: \.self) { date in
                HStack {
                    Text(Self.formatter.string(from: date))
                    Spacer()
                    Text("\(countFor(date))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .monospacedDigit()
                }
                .tag(date as Date?)
            }
        }
        .frame(minWidth: 220)
        .navigationTitle(categoryName)
        .overlay {
            if categoryId == nil {
                ContentUnavailableView(
                    "カテゴリを選択",
                    systemImage: "calendar",
                    description: Text("左から曜日 × 限のカテゴリを選んでください。")
                )
            } else if dateGroups.isEmpty {
                ContentUnavailableView(
                    "まだ撮影なし",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Zoom を開いてツールバーの撮影開始を押してください。")
                )
            }
        }
    }

    private var dateGroups: [Date] {
        guard let cid = categoryId else { return [] }
        let cal = Calendar.current
        let dates = store.screenshots
            .filter { $0.categoryId == cid }
            .map { cal.startOfDay(for: $0.capturedAt) }
        return Array(Set(dates)).sorted(by: >)
    }

    private func countFor(_ date: Date) -> Int {
        guard let cid = categoryId else { return 0 }
        let cal = Calendar.current
        return store.screenshots.lazy.filter {
            $0.categoryId == cid && cal.isDate($0.capturedAt, inSameDayAs: date)
        }.count
    }

    private var categoryName: String {
        guard let cid = categoryId,
              let cat = store.categories.first(where: { $0.id == cid }) else { return "" }
        return cat.displayName
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 (E)"
        return f
    }()
}
