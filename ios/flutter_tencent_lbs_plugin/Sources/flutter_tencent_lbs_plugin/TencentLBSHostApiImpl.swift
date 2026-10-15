import Flutter
import UIKit
import TencentLBS
import CoreLocation

/// Pigeon Host API 实现（Swift 协议），与腾讯定位 SDK 文档对齐。
/// 坐标系：Flutter 统一 0=GCJ02, 1=WGS84 → iOS TencentLBSLocationCoordinateTypeGCJ02=0, WGS84=1
final class TencentLBSHostApiImpl: NSObject, TencentLBSHostApi, TencentLBSLocationManagerDelegate {
    private var locationManager: TencentLBSLocationManager?
    private var flutterApi: TencentLBSFlutterApi?
    private var isListenLocationUpdates = false
    private var callbackThrottle = LocationCallbackThrottle()

    override init() {
        super.init()
    }

    func configure(options: InitOptions) throws -> Bool {
        let accuracy = try desiredAccuracy(locMode: options.locMode, explicitAccuracy: nil)
        let manager = TencentLBSLocationManager()
        manager.delegate = self
        manager.apiKey = options.apiKey
        // enableAntiMockLocation：开启反作弊检查。mockEnable=true 表示允许 Mock，故应关闭反作弊。
        manager.enableAntiMockLocation = !(options.mockEnable ?? false)
        if let accuracy { manager.desiredAccuracy = accuracy }

        if let ct = options.coordinateType {
            manager.coordinateType = ct == 0 ? .GCJ02 : .WGS84
        }
        if let rl = options.requestLevel {
            let level: TencentLBSRequestLevel = {
                switch rl {
                case 0: return .geo
                case 1: return .name
                case 3: return .adminName
                case 4: return .poi
                default: return .adminName
                }
            }()
            manager.requestLevel = level
        }
        locationManager = manager
        return true
    }

    func setUserAgreePrivacy(agree: Bool) throws {
        TencentLBSLocationManager.setUserAgreePrivacy(agree)
    }

    func requestLocationOnce() throws {
        locationManager?.requestLocation(completionBlock: { [weak self] location, err in
            guard let self = self else { return }
            if let e = err {
                let code = (e as NSError).code
                self.flutterApi?.onError(code: Int64(code), message: e.localizedDescription) { _ in }
            } else if let loc = location {
                self.sendLocationToFlutter(loc)
            }
        })
    }

    func startLocationUpdates(request: ContinuousLocationRequest, androidNotificationOptions: AndroidNotificationOptions?) throws {
        guard let manager = locationManager, !isListenLocationUpdates else {
            return
        }
        guard request.intervalMs >= 1000 else {
            throw PigeonError(code: "invalid-argument", message: "intervalMs 必须大于等于 1000，当前值: \(request.intervalMs)", details: nil)
        }
        let accuracy = try desiredAccuracy(locMode: request.locMode, explicitAccuracy: request.iosDesiredAccuracy)
        try validateDistanceFilter(request.iosDistanceFilter)

        if let accuracy { manager.desiredAccuracy = accuracy }
        if let distance = request.iosDistanceFilter { manager.distanceFilter = distance }
        callbackThrottle.updateInterval(milliseconds: request.intervalMs)
        callbackThrottle.reset()
        isListenLocationUpdates = true
        // The SDK's nonzero interval uses a timer configured at start. Receive
        // fresh callbacks instead, so interval changes never require a restart.
        manager.locationCallbackInterval = 0
        manager.allowsBackgroundLocationUpdates = request.backgroundLocation == true
        manager.pausesLocationUpdatesAutomatically = false
        if let rl = request.requestLevel {
            let level: TencentLBSRequestLevel = {
                switch rl {
                case 0: return .geo
                case 1: return .name
                case 3: return .adminName
                case 4: return .poi
                default: return .adminName
                }
            }()
            manager.requestLevel = level
        }
        manager.startUpdatingLocation()
    }

    func updateLocationRequest(update: LocationRequestUpdate?) throws {
        guard let update else { return }
        guard let manager = locationManager, isListenLocationUpdates else {
            throw PigeonError(code: "not-started", message: "请先开启连续定位", details: nil)
        }
        if let interval = update.intervalMs {
            guard interval >= 1000 else {
                throw PigeonError(code: "invalid-argument", message: "intervalMs 必须大于等于 1000，当前值: \(interval)", details: nil)
            }
        }
        // Validate every field before touching the active manager.
        let accuracy = try desiredAccuracy(locMode: update.locMode, explicitAccuracy: update.iosDesiredAccuracy)
        try validateDistanceFilter(update.iosDistanceFilter)

        if let accuracy { manager.desiredAccuracy = accuracy }
        if let distance = update.iosDistanceFilter { manager.distanceFilter = distance }
        if let interval = update.intervalMs { callbackThrottle.updateInterval(milliseconds: interval) }
        if let rl = update.requestLevel {
            let level: TencentLBSRequestLevel = {
                switch rl {
                case 0: return .geo
                case 1: return .name
                case 3: return .adminName
                case 4: return .poi
                default: return .adminName
                }
            }()
            manager.requestLevel = level
        }
        // Keep the existing location session and its background authorization.
    }

    private func desiredAccuracy(locMode: Int64?, explicitAccuracy: Double?) throws -> CLLocationAccuracy? {
        let modeAccuracy: CLLocationAccuracy?
        switch locMode {
        case nil: modeAccuracy = nil
        case 10: modeAccuracy = kCLLocationAccuracyBest
        case 11: modeAccuracy = kCLLocationAccuracyHundredMeters
        case 12:
            throw PigeonError(code: "unsupported-mode", message: "iOS 不支持仅 GPS 定位；请使用高精度或低功耗模式", details: nil)
        default:
            throw PigeonError(code: "invalid-argument", message: "locMode 必须为 10、11 或 12", details: nil)
        }
        if let accuracy = explicitAccuracy,
           !accuracy.isFinite || !(accuracy > 0 || accuracy == kCLLocationAccuracyBest || accuracy == kCLLocationAccuracyBestForNavigation) {
            throw PigeonError(code: "invalid-argument", message: "iosDesiredAccuracy 必须为正数、-1 或 -2", details: nil)
        }
        return explicitAccuracy ?? modeAccuracy
    }

    private func validateDistanceFilter(_ distance: Double?) throws {
        if let distance,
           !distance.isFinite || !(distance >= 0 || distance == kCLDistanceFilterNone) {
            throw PigeonError(code: "invalid-argument", message: "iosDistanceFilter 必须为非负数或 -1", details: nil)
        }
    }

    func stopLocationUpdates() throws {
        isListenLocationUpdates = false
        locationManager?.stopUpdatingLocation()
        callbackThrottle.reset()
    }

    func setBinaryMessenger(_ messenger: FlutterBinaryMessenger) {
        flutterApi = TencentLBSFlutterApi(binaryMessenger: messenger)
    }

    // MARK: - TencentLBSLocationManagerDelegate
    func tencentLBSLocationManager(_ manager: TencentLBSLocationManager, didUpdate location: TencentLBSLocation) {
        guard isListenLocationUpdates,
              callbackThrottle.shouldDeliver(at: ProcessInfo.processInfo.systemUptime) else { return }
        sendLocationToFlutter(location)
    }

    func tencentLBSLocationManager(_ manager: TencentLBSLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        flutterApi?.onError(code: Int64(code), message: error.localizedDescription) { _ in }
    }

    private func sendLocationToFlutter(_ location: TencentLBSLocation) {
        let cl = location.location
        let provider = location.locationProvider
        let unifiedSource = Int64(provider.rawValue)
        let sourceProviderString: String? = {
            switch provider {
            case .GPS: return "gps"
            case .netWork: return "network"
            case .simulated: return "simulated"
            case .accessoryGPS: return "accessory_gps"
            case .accessoryNetwork: return "accessory_network"
            case .unkown: return nil
            @unknown default: return nil
            }
        }()
        let data = LocationData(
            code: 0,
            latitude: cl.coordinate.latitude,
            longitude: cl.coordinate.longitude,
            altitude: cl.altitude,
            accuracy: cl.horizontalAccuracy,
            horizontalAccuracy: cl.horizontalAccuracy,
            verticalAccuracy: cl.verticalAccuracy,
            speed: cl.speed >= 0 ? cl.speed : nil,
            bearing: cl.course >= 0 ? cl.course : nil,
            address: location.address,
            name: location.name,
            timeIso: nil,
            timeMs: Int64(cl.timestamp.timeIntervalSince1970 * 1000),
            sourceProvider: sourceProviderString,
            locationSource: unifiedSource
        )
        flutterApi?.onLocation(location: data) { _ in }
    }
}
