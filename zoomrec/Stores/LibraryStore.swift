import Foundation
import AppKit
import CoreGraphics

enum CategoryDeletionMode {
    case reassignToUncategorized
    case deleteAllScreenshots
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var categories: [DayPeriodCategory] = []
    @Published private(set) var screenshots: [Screenshot] = []

    let baseURL: URL
    let imagesURL: URL
    let libraryURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("zoomrec", isDirectory: true)
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        libraryURL = baseURL.appendingPathComponent("library.json")
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
        purgeMissingFiles()
    }

    func purgeMissingFiles() {
        let fm = FileManager.default
        let before = screenshots.count
        screenshots.removeAll { !fm.fileExists(atPath: imageURL(for: $0).path) }
        if screenshots.count != before {
            NSLog("zoomrec: purged \(before - screenshots.count) missing image entries")
            persist()
        }
    }

    func imageURL(for shot: Screenshot) -> URL {
        imagesURL.appendingPathComponent(shot.filename)
    }

    func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do {
            let lib = try JSONDecoder.app.decode(Library.self, from: data)
            categories = lib.categories
            screenshots = lib.screenshots
        } catch {
            NSLog("zoomrec: library decode failed: \(error)")
        }
    }

    func persist() {
        let lib = Library(categories: categories, screenshots: screenshots)
        do {
            let data = try JSONEncoder.app.encode(lib)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            NSLog("zoomrec: library persist failed: \(error)")
        }
    }

    func save(image: CGImage, at date: Date) throws {
        let category = Categorizer.resolveCategory(for: date, in: &categories)
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let url = imagesURL.appendingPathComponent(filename)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "zoomrec", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        try png.write(to: url, options: .atomic)
        screenshots.append(Screenshot(id: id, filename: filename, capturedAt: date, categoryId: category.id))
        persist()
    }

    func move(screenshot: Screenshot, to categoryId: UUID) {
        move([screenshot], to: categoryId)
    }

    func move(_ targets: [Screenshot], to categoryId: UUID) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        var changed = false
        for i in screenshots.indices where ids.contains(screenshots[i].id) {
            if screenshots[i].categoryId != categoryId {
                screenshots[i].categoryId = categoryId
                changed = true
            }
        }
        if changed { persist() }
    }

    func delete(_ targets: [Screenshot]) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        for shot in screenshots where ids.contains(shot.id) {
            try? FileManager.default.removeItem(at: imageURL(for: shot))
        }
        screenshots.removeAll { ids.contains($0.id) }
        persist()
    }

    func screenshots(in categoryId: UUID, on date: Date) -> [Screenshot] {
        let cal = Calendar.current
        return screenshots.filter {
            $0.categoryId == categoryId && cal.isDate($0.capturedAt, inSameDayAs: date)
        }
    }

    func addCategory(weekday: Int, period: Int, customName: String? = nil) {
        if categories.contains(where: {
            $0.weekday == weekday && $0.period == period && $0.customName == customName
        }) { return }
        let name = customName?.isEmpty == false ? customName : nil
        categories.append(DayPeriodCategory(id: UUID(), weekday: weekday, period: period, customName: name))
        persist()
    }

    func updateCategory(id: UUID, weekday: Int, period: Int, customName: String?) {
        guard let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].weekday = weekday
        categories[idx].period = period
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        categories[idx].customName = (trimmed?.isEmpty == false) ? trimmed : nil
        persist()
    }

    func deleteCategory(id: UUID, mode: CategoryDeletionMode) {
        guard let cat = categories.first(where: { $0.id == id }) else { return }
        let affected = screenshots.filter { $0.categoryId == id }
        switch mode {
        case .reassignToUncategorized:
            let uncatId = ensureUncategorizedCategoryId()
            for i in screenshots.indices where screenshots[i].categoryId == id {
                screenshots[i].categoryId = uncatId
            }
        case .deleteAllScreenshots:
            let ids = Set(affected.map(\.id))
            for shot in affected {
                try? FileManager.default.removeItem(at: imageURL(for: shot))
            }
            screenshots.removeAll { ids.contains($0.id) }
        }
        if !cat.isUncategorized {
            categories.removeAll { $0.id == id }
        }
        persist()
    }

    private func ensureUncategorizedCategoryId() -> UUID {
        if let existing = categories.first(where: { $0.isUncategorized }) {
            return existing.id
        }
        let new = DayPeriodCategory(id: UUID(), weekday: 0, period: 0, customName: nil)
        categories.append(new)
        return new.id
    }
}

extension JSONEncoder {
    static let app: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let app: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
