import Foundation
import AppKit
import CoreGraphics

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
        guard let idx = screenshots.firstIndex(where: { $0.id == screenshot.id }) else { return }
        screenshots[idx].categoryId = categoryId
        persist()
    }

    func addCategory(weekday: Int, period: Int) {
        if categories.contains(where: { $0.weekday == weekday && $0.period == period }) { return }
        categories.append(DayPeriodCategory(id: UUID(), weekday: weekday, period: period))
        persist()
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
