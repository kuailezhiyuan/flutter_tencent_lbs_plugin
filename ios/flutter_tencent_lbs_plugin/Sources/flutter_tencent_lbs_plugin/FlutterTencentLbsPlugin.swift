import Flutter
import UIKit

public class FlutterTencentLBSPlugin: NSObject, FlutterPlugin {
    private let api = TencentLBSHostApiImpl()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterTencentLBSPlugin()
        instance.api.setBinaryMessenger(registrar.messenger())
        TencentLBSHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance.api)
        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        api.dispose()
        TencentLBSHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    }
}
