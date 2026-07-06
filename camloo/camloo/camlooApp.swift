import SwiftUI

@main
struct CamlooApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var camera = CameraManager()
    @StateObject private var sysext = SystemExtensionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(camera)
                .environmentObject(sysext)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    camera.requestAuthorizationIfNeeded()
                    sysext.refreshInstalledState()
                }
        }
    }
}
