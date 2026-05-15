import SwiftUI

struct SessionList: View {
    @EnvironmentObject var store: LibraryStore
    let categoryId: UUID?
    @Binding var selection: Date?
    @State private var deletingDate: Date?

    var body: some View {
        List(selection: $selection) {
            ForEach(dateGroups, id: \.self) { date in
                let count = countFor(date)
                HStack {
                    Text(Self.formatter.string(from: date))
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .monospacedDigit()
                }
                .tag(date as Date?)
                .contextMenu {
                    if let cid = categoryId {
                        Menu("この日の \(count) 件を別の時限に移動") {
                            ForEach(otherCategories(except: cid)) { cat in
                                Button(cat.displayName) {
                                    let shots = store.screenshots(in: cid, on: date)
                                    store.move(shots, to: cat.id)
                                }
                            }
                        }
                        Divider()
                        Button("この日の \(count) 件を削除…", role: .destructive) {
                            deletingDate = date
                        }
                    }
                }
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
        .confirmationDialog(
            deletingDate.map { "\(Self.formatter.string(from: $0))のスクショを削除" } ?? "削除",
            isPresented: Binding(
                get: { deletingDate != nil },
                set: { if !$0 { deletingDate = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingDate
        ) { date in
            if let cid = categoryId {
                let shots = store.screenshots(in: cid, on: date)
                Button("\(shots.count) 件を削除", role: .destructive) {
                    store.delete(shots)
                    if selection == date { selection = nil }
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { date in
            if let cid = categoryId {
                let n = store.screenshots(in: cid, on: date).count
                Text("\(n) 件の画像ファイルが削除されます。元に戻せません。")
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

    private func otherCategories(except cid: UUID) -> [DayPeriodCategory] {
        store.categories
            .filter { $0.id != cid }
            .sorted { $0.sortKey < $1.sortKey }
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
