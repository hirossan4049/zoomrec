import SwiftUI

struct CategorySidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selection: UUID?
    @Binding var showingNewCategory: Bool

    var body: some View {
        List(selection: $selection) {
            Section("カテゴリ") {
                ForEach(sortedCategories) { cat in
                    HStack {
                        Text(cat.displayName)
                        Spacer()
                        Text("\(countFor(cat))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .tag(cat.id as UUID?)
                    .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                        handleDrop(providers: providers, categoryId: cat.id)
                    }
                }
            }

            Section {
                Button {
                    showingNewCategory = true
                } label: {
                    Label("新規カテゴリ", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private var sortedCategories: [DayPeriodCategory] {
        store.categories.sorted { $0.sortKey < $1.sortKey }
    }

    private func countFor(_ cat: DayPeriodCategory) -> Int {
        store.screenshots.lazy.filter { $0.categoryId == cat.id }.count
    }

    private func handleDrop(providers: [NSItemProvider], categoryId: UUID) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if let shot = store.screenshots.first(where: {
                        store.imageURL(for: $0).standardizedFileURL == url.standardizedFileURL
                    }) {
                        store.move(screenshot: shot, to: categoryId)
                    }
                }
            }
        }
        return true
    }
}

struct NewCategorySheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var weekday = 1
    @State private var period = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新規カテゴリ").font(.title2.bold())

            HStack {
                Text("曜日").frame(width: 40, alignment: .leading)
                Picker("", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(weekdayKanji[$0] ?? "?").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            HStack {
                Text("限").frame(width: 40, alignment: .leading)
                Picker("", selection: $period) {
                    ForEach(1...7, id: \.self) { Text("\($0)限").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("追加") {
                    store.addCategory(weekday: weekday, period: period)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
