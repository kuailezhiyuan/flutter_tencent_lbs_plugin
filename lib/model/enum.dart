// Preserve the public SDK constant names.
// ignore_for_file: constant_identifier_names

// 与腾讯定位 SDK 文档保持一致，避免与原生常量混淆
// Android: https://mapapi.qq.com/sdk/locationSDK/Android/doc/com/tencent/map/geolocation/package-summary.html
// iOS: TencentLBSLocationManager.h

/// 坐标系类型（双端统一：0=GCJ02 火星坐标，1=WGS84 地球坐标）
/// 原生层会映射到各自 SDK 常量：
/// Android: COORDINATE_TYPE_GCJ02=1, COORDINATE_TYPE_WGS84=0
/// iOS: TencentLBSLocationCoordinateTypeGCJ02=0, TencentLBSLocationCoordinateTypeWGS84=1
class TencentLBSLocationCoordinateType {
  /// 火星坐标（国测局坐标）
  static const int GCJ02 = 0;

  /// 地球坐标（GPS 坐标）；海外无论设置哪种均返回地球坐标
  static const int WGS84 = 1;
}

/// 定位结果信息级别（与 TencentLocationRequest.requestLevel / iOS requestLevel 一致）
class TencentLBSRequestLevel {
  /// 0 号接口：仅经纬度
  static const int Geo = 0;

  /// 1 号接口：经纬度 + 位置名称 + 地址
  static const int Name = 1;

  /// 3 号接口：经纬度 + 行政区划 + 地址 + 名称
  static const int AdminName = 3;

  /// 4 号接口：经纬度 + 行政区划 + 周边 POI（无 name/address）
  static const int Poi = 4;
}

/// 定位模式。Android 使用 TencentLocationRequest；iOS 使用 desiredAccuracy。
class TencentLBSLocMode {
  /// Android：网络 + 卫星；iOS：kCLLocationAccuracyBest。
  static const int HIGH_ACCURACY_MODE = 10;

  /// Android：仅网络；iOS：百米精度要求，不保证关闭 GPS。
  static const int ONLY_NETWORK_MODE = 11;

  /// 双端低功耗模式。与 ONLY_NETWORK_MODE 使用相同的值。
  static const int LOW_POWER_MODE = ONLY_NETWORK_MODE;

  /// 仅 Android 支持。iOS 无法指定只使用 GPS，会返回 unsupported-mode。
  static const int ONLY_GPS_MODE = 12;
}

/// iOS desiredAccuracy 的常用值，单位米。精度是请求目标，不是结果保证。
class TencentLBSIosAccuracy {
  static const double bestForNavigation = -2;
  static const double best = -1;
  static const double nearestTenMeters = 10;
  static const double hundredMeters = 100;
  static const double kilometer = 1000;
  static const double threeKilometers = 3000;
}

/// 定位来源（双端统一）
/// iOS: TencentLBSLocationProvider；Android: TencentLocation.getSourceProvider() 映射到此
/// 参考：https://lbs.qq.com/mobile/iosLocationSDK/iosGeoGuide/geoCreate#3
///       https://mapapi.qq.com/sdk/locationSDK/Android/doc/com/tencent/map/geolocation/TencentLocation.html
class LocationSource {
  /// 来源未知
  static const int Unknown = -1;

  /// 手机 GPS / 卫星（Android: GPS_PROVIDER、BEIDOU_PROVIDER）
  static const int Gps = 0;

  /// 手机网络（Android: NETWORK_PROVIDER、WIFI_PROVIDER、CELL_PROVIDER、COARSE_PROVIDER、FUSED_PROVIDER）
  static const int Network = 1;

  /// 模拟/作弊定位（Android: FAKE）
  static const int Simulated = 2;

  /// 外设 GPS
  static const int AccessoryGps = 3;

  /// 外设网络
  static const int AccessoryNetwork = 4;
}
