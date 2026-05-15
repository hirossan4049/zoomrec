import SwiftUI
import AppKit

struct ThumbnailItem: View {
    @EnvironmentObject var store: LibraryStore
    let shot: Screenshot
    var onTap: () -> Void

    var body: some View {
        let url = store.imageURL(for: shot)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.05))
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(height: 120)

            Text(Self.timeFmt.string(from: shot.capturedAt))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.07))
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Menu("別の時限に移動") {
                ForEach(store.categories.sorted(by: { $0.sortKey < $1.sortKey })) { cat in
                    Button(cat.displayName) {
                        store.move(screenshot: shot, to: cat.id)
                    }
                    .disabled(cat.id == shot.categoryId)
                }
            }
            Button("Finder で表示") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("画像をコピー") {
                if let img = NSImage(contentsOf: url) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([img])
                }
            }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
