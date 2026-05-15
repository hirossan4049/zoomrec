import SwiftUI

struct ContentView: View {
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
            NewCategorySheet()
        }
        .onChange(of: selectedCategoryId) { _, _ in
            selectedDate = nil
        }
    }
}
