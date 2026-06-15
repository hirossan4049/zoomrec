import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ScreenshotsView()
                .tabItem { Label("スクショ", systemImage: "camera") }

            LiveTranscriptionView()
                .tabItem { Label("字幕", systemImage: "captions.bubble") }
        }
    }
}

/// 既存のスクショ撮影 UI（カテゴリ / 日付 / サムネイル + 撮影ステータスバー）。
struct ScreenshotsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var capture: CaptureService
    @State private var selectedCategoryId: UUID?
    @State private var selectedDate: Date?
    @State private var showingNewCategory = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                CategorySidebar(
                    selection: $selectedCategoryId,
                    showingNewCategory: $showingNewCategory
                )
            } content: {
                SessionList(categoryId: selectedCategoryId, selection: $selectedDate)
            } detail: {
                ThumbnailGrid(categoryId: selectedCategoryId, date: selectedDate)
            }
            CaptureStatusBar()
        }
        .sheet(isPresented: $showingNewCategory) {
            CategoryFormSheet()
        }
        .onChange(of: selectedCategoryId) { _, _ in
            selectedDate = nil
        }
    }
}
