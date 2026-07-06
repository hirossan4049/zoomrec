import Foundation
import CoreMediaIO

/// 仮想カメラの Provider。デバイスを 1 つ登録する。
class CameraProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: CameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)

        // 表示名は App Group 経由の共有設定から取得（未設定なら既定値）。
        let name = Camloo.defaults.string(forKey: Camloo.DefaultsKey.cameraName)
            ?? Camloo.Defaults.cameraName

        deviceSource = CameraDeviceSource(localizedName: name)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("camloo: failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "camloo"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
