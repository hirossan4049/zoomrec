import SwiftUI

struct CategorySidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var selection: UUID?
    @Binding var showingNewCategory: Bool
    @State private var editingCategory: DayPeriodCategory?
    @State private var deletingCategory: DayPeriodCategory?

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
                    .contextMenu {
                        Button("名前を編集") { editingCategory = cat }
                        if !cat.isUncategorized {
                            Divider()
                            Button("削除…", role: .destructive) { deletingCategory = cat }
                        }
                    }
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
        .sheet(item: $editingCategory) { cat in
            CategoryFormSheet(editing: cat)
        }
        .confirmationDialog(
            deletingCategory.map { "「\($0.displayName)」を削除" } ?? "削除",
            isPresented: Binding(
                get: { deletingCategory != nil },
                set: { if !$0 { deletingCategory = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingCategory
        ) { cat in
            Button("スクショは未分類へ移動") {
                store.deleteCategory(id: cat.id, mode: .reassignToUncategorized)
                if selection == cat.id { selection = nil }
            }
            Button("スクショごと削除", role: .destructive) {
                store.deleteCategory(id: cat.id, mode: .deleteAllScreenshots)
                if selection == cat.id { selection = nil }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { cat in
            let n = store.screenshots.filter { $0.categoryId == cat.id }.count
            Text("「\(cat.displayName)」のスクショ \(n) 件があります。")
        }
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

struct CategoryFormSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let editing: DayPeriodCategory?
    @State private var weekday: Int
    @State private var period: Int
    @State private var customName: String

    init(editing: DayPeriodCategory? = nil) {
        self.editing = editing
        _weekday = State(initialValue: max(1, editing?.weekday ?? 1))
        _period = State(initialValue: max(1, editing?.period ?? 1))
        _customName = State(initialValue: editing?.customName ?? "")
    }

    private var isEdit: Bool { editing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEdit ? "カテゴリを編集" : "新規カテゴリ")
                .font(.title2.bold())

            HStack {
                Text("曜日").frame(width: 80, alignment: .leading)
                Picker("", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(weekdayKanji[$0] ?? "?").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            HStack {
                Text("限").frame(width: 80, alignment: .leading)
                Picker("", selection: $period) {
                    ForEach(1...7, id: \.self) { Text("\($0)限").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            HStack {
                Text("カスタム名").frame(width: 80, alignment: .leading)
                TextField("任意 (例: 線形代数)", text: $customName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("カスタム名を入れるとサイドバーの表示がそれに置き換わります。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEdit ? "保存" : "追加") {
                    let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = trimmed.isEmpty ? nil : trimmed
                    if let editing {
                        store.updateCategory(
                            id: editing.id,
                            weekday: weekday,
                            period: period,
                            customName: name
                        )
                    } else {
                        store.addCategory(weekday: weekday, period: period, customName: name)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
