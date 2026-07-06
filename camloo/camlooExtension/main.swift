import Foundation
import CoreMediaIO

// Camera Extension のエントリポイント。
// Provider を起動して仮想カメラサービスを開始し、run loop で常駐する。
let providerSource = CameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
