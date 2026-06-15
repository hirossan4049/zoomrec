import SwiftUI

@main
struct ZoomRecApp: App {
    @StateObject private var store: LibraryStore
    @StateObject private var capture: CaptureService
    @StateObject private var transcription = LiveTranscriptionService()

    init() {
        let store = LibraryStore()
        _store = StateObject(wrappedValue: store)
        _capture = StateObject(wrappedValue: CaptureService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(capture)
                .environmentObject(transcription)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}
