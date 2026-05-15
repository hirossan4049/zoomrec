import SwiftUI
import AppKit

struct ThumbnailItem: View, Equatable {
    @EnvironmentObject var store: LibraryStore
    let shot: Screenshot
    let isSelected: Bool
    let actionTargets: () -> [Screenshot]
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onDeleteRequest: ([Screenshot]) -> Void

    @State private var image: NSImage?

    static func == (lhs: ThumbnailItem, rhs: ThumbnailItem) -> Bool {
        lhs.shot.id == rhs.shot.id
            && lhs.shot.categoryId == rhs.shot.categoryId
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        let url = store.imageURL(for: shot)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.05))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(height: 120)

            Text(Self.timeFmt.string(from: shot.capturedAt))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.22)
                      : Color.gray.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture { onClick() }
        .onDrag {
            NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu { contextMenuContent(url: url) }
        .task(id: shot.id) {
            await loadImageIfNeeded(url: url)
        }
    }

    private func loadImageIfNeeded(url: URL) async {
        guard image == nil else { return }
        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        image = loaded
    }

    @ViewBuilder
    private func contextMenuContent(url: URL) -> some View {
        let targets = actionTargets()
        let n = targets.count
        let prefix = n > 1 ? "選択中の \(n) 件を" : ""

        Menu("\(prefix)別の時限に移動") {
            ForEach(store.categories.sorted(by: { $0.sortKey < $1.sortKey })) { cat in
                Button(cat.displayName) {
                    store.move(targets, to: cat.id)
                }
                .disabled(n == 1 && cat.id == shot.categoryId)
            }
        }

        Button(n > 1 ? "Finder で表示 (\(n) 件)" : "Finder で表示") {
            let urls = targets.map { store.imageURL(for: $0) }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }

        Button(n > 1 ? "URLをコピー (\(n) 件)" : "画像をコピー") {
            let pb = NSPasteboard.general
            pb.clearContents()
            if n > 1 {
                pb.writeObjects(targets.map { store.imageURL(for: $0) as NSURL })
            } else if let img = image ?? NSImage(contentsOf: url) {
                pb.writeObjects([img])
            }
        }

        Divider()

        Button("\(prefix)削除…", role: .destructive) {
            onDeleteRequest(targets)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
