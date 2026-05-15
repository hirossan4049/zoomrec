import SwiftUI
import AppKit

private struct ThumbnailFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ThumbnailGrid: View {
    @EnvironmentObject var store: LibraryStore
    let categoryId: UUID?
    let date: Date?
    @State private var preview: PreviewItem?
    @State private var selection: Set<UUID> = []
    @State private var anchor: UUID?
    @State private var thumbnailFrames: [UUID: CGRect] = [:]
    @State private var rubberBandStart: CGPoint?
    @State private var rubberBandCurrent: CGPoint?
    @State private var rubberBandPreSelection: Set<UUID> = []
    @State private var deleteTargets: [Screenshot] = []
    @State private var showingDeleteConfirm = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(visibleShots) { shot in
                        ThumbnailItem(
                            shot: shot,
                            isSelected: selection.contains(shot.id),
                            actionTargets: { actionTargets(for: shot) },
                            onClick: { handleClick(shot) },
                            onDoubleClick: {
                                preview = PreviewItem(url: store.imageURL(for: shot))
                            },
                            onDeleteRequest: { requestDelete($0) }
                        )
                        .equatable()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ThumbnailFramesKey.self,
                                    value: [shot.id: proxy.frame(in: .named("grid"))]
                                )
                            }
                        )
                    }
                }
                .padding(12)

                if let rect = rubberBandRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(
                            Rectangle().stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection.removeAll(); focused = true }
                    .gesture(rubberBandGesture)
            )
            .coordinateSpace(name: "grid")
            .onPreferenceChange(ThumbnailFramesKey.self) { thumbnailFrames = $0 }
        }
        .frame(minWidth: 460, minHeight: 400)
        .overlay(alignment: .topTrailing) { selectionBadge }
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
        .confirmationDialog(
            "\(deleteTargets.count) 件の画像を削除しますか？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                let ids = Set(deleteTargets.map(\.id))
                store.delete(deleteTargets)
                selection.subtract(ids)
                deleteTargets = []
            }
            Button("キャンセル", role: .cancel) { deleteTargets = [] }
        } message: {
            Text("画像ファイルは ~/Library/Application Support/zoomrec/images から削除されます。元に戻せません。")
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: categoryId) { _, _ in selection.removeAll() }
        .onChange(of: date) { _, _ in selection.removeAll() }
        .onKeyPress(.escape) {
            selection.removeAll()
            return .handled
        }
        .onKeyPress(.delete) {
            if !selection.isEmpty {
                requestDelete(visibleShots.filter { selection.contains($0.id) })
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection = Set(visibleShots.map(\.id))
            return .handled
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if selection.count > 1 {
            Text("\(selection.count) 件選択中")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                .padding(12)
        }
    }

    private var rubberBandRect: CGRect? {
        guard let start = rubberBandStart, let current = rubberBandCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private var rubberBandGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { value in
                let flags = NSEvent.modifierFlags
                if rubberBandStart == nil {
                    rubberBandStart = value.startLocation
                    if flags.contains(.shift) || flags.contains(.command) {
                        rubberBandPreSelection = selection
                    } else {
                        rubberBandPreSelection = []
                        selection = []
                    }
                    focused = true
                }
                rubberBandCurrent = value.location
                let rect = rubberBandRect ?? .zero
                let hits = Set(thumbnailFrames.compactMap { id, frame in
                    rect.intersects(frame) ? id : nil
                })
                if flags.contains(.command) {
                    selection = rubberBandPreSelection.symmetricDifference(hits)
                } else if flags.contains(.shift) {
                    selection = rubberBandPreSelection.union(hits)
                } else {
                    selection = hits
                }
            }
            .onEnded { _ in
                rubberBandStart = nil
                rubberBandCurrent = nil
                rubberBandPreSelection = []
            }
    }

    private var visibleShots: [Screenshot] {
        guard let cid = categoryId, let date else { return [] }
        let cal = Calendar.current
        return store.screenshots
            .filter { $0.categoryId == cid && cal.isDate($0.capturedAt, inSameDayAs: date) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func actionTargets(for shot: Screenshot) -> [Screenshot] {
        if selection.contains(shot.id) && selection.count > 1 {
            return visibleShots.filter { selection.contains($0.id) }
        }
        return [shot]
    }

    private func handleClick(_ shot: Screenshot) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift),
           let anchorId = anchor,
           let a = visibleShots.firstIndex(where: { $0.id == anchorId }),
           let b = visibleShots.firstIndex(where: { $0.id == shot.id }) {
            let lo = min(a, b), hi = max(a, b)
            selection = Set(visibleShots[lo...hi].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(shot.id) {
                selection.remove(shot.id)
            } else {
                selection.insert(shot.id)
            }
            anchor = shot.id
        } else {
            selection = [shot.id]
            anchor = shot.id
        }
    }

    private func requestDelete(_ targets: [Screenshot]) {
        guard !targets.isEmpty else { return }
        deleteTargets = targets
        showingDeleteConfirm = true
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
