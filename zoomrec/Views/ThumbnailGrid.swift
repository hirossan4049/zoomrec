import SwiftUI

struct ThumbnailGrid: View {
    @EnvironmentObject var store: LibraryStore
    let categoryId: UUID?
    let date: Date?
    @State private var preview: PreviewItem?

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                ForEach(visibleShots) { shot in
                    ThumbnailItem(shot: shot) {
                        preview = PreviewItem(url: store.imageURL(for: shot))
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 400)
        .overlay {
            if date == nil {
                ContentUnavailableView(
                    "日付を選択",
                    systemImage: "calendar.badge.clock",
                    description: Text("中央から日付を選ぶとスクリーンショットが表示されます。")
                )
            } else if visibleShots.isEmpty {
                ContentUnavailableView(
                    "この日のスクショなし",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
        }
        .sheet(item: $preview) { item in
            ImagePreview(url: item.url) { preview = nil }
        }
    }

    private var visibleShots: [Screenshot] {
        guard let cid = categoryId, let date else { return [] }
        let cal = Calendar.current
        return store.screenshots
            .filter { $0.categoryId == cid && cal.isDate($0.capturedAt, inSameDayAs: date) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}

private struct PreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ImagePreview: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.04)
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Finder で表示", systemImage: "folder")
                }
                Spacer()
                Button("閉じる", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 540)
    }
}
