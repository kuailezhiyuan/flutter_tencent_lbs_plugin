import 'package:pigeon/pigeon.dart';

// 生成命令: dart run pigeon --input pigeons/location_api.dart
// 参数与腾讯定位 SDK 文档对齐，注释仅引用 SDK 文档内容：
// Android: https://mapapi.qq.com/sdk/locationSDK/Android/doc/com/tencent/map/geolocation/package-summary.html
//         TencentLocationRequest, TencentLocation, TencentLocationManagerOptions
// iOS:    https://mapapi.qq.com/sdk/locationSDK/iOS/doc/appledoc/html/index.html

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/location_pigeon.dart',
    kotlinOut:
        'android/src/main/kotlin/com/flutter_tencent_lbs_plugin/pigeon/LocationPigeon.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.flutter_tencent_lbs_plugin.pigeon',
    ),
    swiftOut:
        'ios/flutter_tencent_lbs_plugin/Sources/flutter_tencent_lbs_plugin/pigeon/LocationPigeon.swift',
    swiftOptions: SwiftOptions(),
  ),
)
// ========== 常量对照（SDK 文档） ==========
// coordinateType: 0=GCJ02 火星坐标，1=WGS84 地球坐标（Android TencentLocationManager / iOS TencentLBSLocationCoordinateType）
// requestLevel:  0=GEO 仅经纬度，1=NAME 经纬度+名称+地址，3=ADMIN_AREA 经纬度+行政区划+地址+名称，4=POI 经纬度+行政区划+附近POI（Android TencentLocationRequest）
// locMode(Android): 10=HIGH_ACCURACY_MODE 高精度，11=ONLY_NETWORK_MODE 仅网络，12=ONLY_GPS_MODE 仅GPS
/// 初始化参数。对应 Android TencentLocationManagerOptions + TencentLocationManager + TencentLocationRequest 的初始设置；iOS TencentLBSLocationManager 的 apiKey、coordinateType、requestLevel 等。
class InitOptions {
  /// 腾讯开放平台申请的 Key。Android: TencentLocationManagerOptions.setKey；iOS: apiKey。
  String apiKey;

  /// 坐标系类型。0=GCJ02（火星坐标，大陆返回 GCJ02 大陆外返回 WGS84）；1=WGS84（地球坐标，均返回 WGS84）。Android: TencentLocationManager.coordinateType；iOS: TencentLBSLocationCoordinateType。
  int? coordinateType;

  /// 是否允许 Mock 定位。Android: TencentLocationManager.setMockEnable。
  bool? mockEnable;

  /// 定位结果信息级别。不同 level 结果信息完整程度不同，信息越多消耗流量越多。Android: TencentLocationRequest.setRequestLevel。0=仅经纬度，1=经纬度+位置名称+地址，3=经纬度+行政区划+地址+名称，4=经纬度+行政区划+附近POI。
  int? requestLevel;

  /// 定位模式。Android: TencentLocationRequest.setLocMode，10=高精度、11=仅网络、12=仅GPS。iOS: 10=Best、11=HundredMeters，12 不支持。
  int? locMode;

  /// 是否允许使用 GPS（仅 Android）。TencentLocationRequest.setAllowGPS，默认允许。允许时室外可提升精度约3-10米，首次较慢耗电较高。仅对高精度定位模式生效。
  bool? allowGps;

  /// 是否启动室内定位（仅 Android）。TencentLocationRequest.setIndoorLocationMode。
  bool? indoorLocationMode;

  /// 首次定位是否等待卫星定位结果（仅 Android）。TencentLocationRequest.setGpsFirst，默认 false。为 true 时首次定位会等待卫星结果，超时后返回网络定位结果。仅高精度模式生效。
  bool? gpsFirst;

  /// 卫星定位优先时，等待卫星定位结果的超时时间（仅 Android）。TencentLocationRequest.setGpsFirstTimeOut，单位 ms，最多 60s。
  int? gpsFirstTimeOutMs;

  InitOptions({
    required this.apiKey,
    this.coordinateType,
    this.mockEnable,
    this.requestLevel,
    this.locMode,
    this.allowGps,
    this.indoorLocationMode,
    this.gpsFirst,
    this.gpsFirstTimeOutMs,
  });
}

/// 连续定位请求参数。对应 Android TencentLocationRequest；iOS 连续定位时的 interval、requestLevel 等。
class ContinuousLocationRequest {
  /// 定位周期（位置监听器回调周期），单位 ms。Android: TencentLocationRequest.setInterval。大于 0 时按周期定时回调；等于 0 时仅当有新的定位结果时回调。文档建议 5000-10000ms，不建议 1000ms 以下，且不得小于 1000ms。
  int intervalMs;

  /// 定位结果信息级别，同 InitOptions.requestLevel。不传则使用 init 时的值。
  int? requestLevel;

  /// 双端定位模式，同 InitOptions.locMode。
  int? locMode;

  /// 是否允许使用 GPS（仅 Android），同 InitOptions.allowGps。
  bool? allowGps;

  /// 是否允许使用缓存（仅 Android）。TencentLocationRequest.setAllowCache。允许时用户移动范围较小时可减少网络请求、节省电量和流量；长时间连续定位建议允许，单次定位建议不使用。
  bool? allowCache;

  /// 首次是否等待卫星结果（仅 Android），同 InitOptions.gpsFirst。
  bool? gpsFirst;

  /// 卫星优先超时时间 ms（仅 Android），同 InitOptions.gpsFirstTimeOutMs。
  int? gpsFirstTimeOutMs;

  /// 是否后台定位。为 true 时 Android 需配合前台通知（enableForegroundLocation）；iOS 需配置后台定位能力。
  bool? backgroundLocation;

  /// iOS desiredAccuracy，单位米；-1=Best、-2=BestForNavigation，或正数。覆盖 locMode 默认精度。
  double? iosDesiredAccuracy;

  /// iOS distanceFilter，单位米；-1=不进行距离过滤，或非负数。
  double? iosDistanceFilter;

  ContinuousLocationRequest({
    required this.intervalMs,
    this.requestLevel,
    this.locMode,
    this.allowGps,
    this.allowCache,
    this.gpsFirst,
    this.gpsFirstTimeOutMs,
    this.backgroundLocation,
    this.iosDesiredAccuracy,
    this.iosDistanceFilter,
  });
}

/// 连续定位过程中可更新的参数，仅传需要修改的字段。Android 使用 changeCallbackInterval 或再次 requestLocationUpdates，不先 removeUpdates；iOS 原地修改精度、距离和信息级别，间隔由插件节流新回调。
class LocationRequestUpdate {
  int? intervalMs;
  int? requestLevel;
  int? locMode;
  int? gpsFirstTimeOutMs;
  bool? allowGps;
  bool? allowCache;
  bool? gpsFirst;
  double? iosDesiredAccuracy;
  double? iosDistanceFilter;
  LocationRequestUpdate({
    this.intervalMs,
    this.requestLevel,
    this.locMode,
    this.gpsFirstTimeOutMs,
    this.allowGps,
    this.allowCache,
    this.gpsFirst,
    this.iosDesiredAccuracy,
    this.iosDistanceFilter,
  });
}

/// Android 后台定位时的前台通知配置。Android 后台定位需前台服务并显示通知，通过 TencentLocationManager.enableForegroundLocation(notifId, notification) 绑定；id 为通知 ID，channelId/channelName 为通知渠道，notificationTitle/notificationText 为通知标题与内容。
class AndroidNotificationOptions {
  /// 前台定位通知 ID，用于 enableForegroundLocation(id, notification)。
  int id;

  /// 通知渠道 ID（Android NotificationChannel）。
  String channelId;

  /// 通知渠道名称。
  String channelName;

  /// 通知渠道描述（可选）。
  String? channelDescription;

  /// 通知标题。
  String notificationTitle;

  /// 通知内容（可选）。
  String? notificationText;

  /// 是否振动。
  bool? enableVibration;

  /// 是否播放声音。
  bool? playSound;

  /// 是否显示时间。
  bool? showWhen;
  AndroidNotificationOptions({
    required this.id,
    required this.channelId,
    required this.channelName,
    this.channelDescription,
    required this.notificationTitle,
    this.notificationText,
    this.enableVibration,
    this.playSound,
    this.showWhen,
  });
}

/// 定位结果。对应 Android TencentLocation 接口、iOS TencentLBSLocation 返回字段。
class LocationData {
  /// 错误码。Android TencentLocation：0=ERROR_OK 定位成功，1=ERROR_NETWORK 网络问题，2=ERROR_BAD_JSON GPS/WiFi/基站错误，4=ERROR_WGS84 无法进行坐标转换，404=ERROR_UNKNOWN 未知原因。
  int? code;

  /// 纬度。TencentLocation.getLatitude。
  double? latitude;

  /// 经度。TencentLocation.getLongitude。
  double? longitude;

  /// 海拔，单位 m。TencentLocation.getAltitude，仅当位置来自 GPS 时可能有效。
  double? altitude;

  /// 精度，单位 m（水平精度）。TencentLocation.getAccuracy / CLLocation.horizontalAccuracy。
  double? accuracy;

  /// 水平精度，单位 m。与 accuracy 同源，语义明确。
  double? horizontalAccuracy;

  /// 垂直精度（海拔精度），单位 m。仅 iOS CLLocation.verticalAccuracy 有值，Android 为 null。
  double? verticalAccuracy;

  /// 移动速度，单位 m/s。TencentLocation.getSpeed，仅当位置来自 GPS 时可能有效。
  double? speed;

  /// 方向/朝向，单位度（0～360）。TencentLocation.getBearing / CLLocation.course，仅当位置来自 GPS 时可能有效。
  double? bearing;

  /// 位置地址。TencentLocation.getAddress，仅当 request level 为 NAME 或 ADMIN_AREA 时非 null。
  String? address;

  /// 位置名称。TencentLocation.getName，仅当 request level 为 NAME 或 ADMIN_AREA 时非 null。
  String? name;

  /// 时间 ISO 字符串（可选，非 SDK 必返字段）。
  String? timeIso;

  /// 当前位置生成时间，毫秒时间戳。TencentLocation.getTime。
  int? timeMs;

  /// 位置细分来源（原生原始值）。Android: TencentLocation.getSourceProvider()；iOS 可为 null，以 locationSource 为准。
  String? sourceProvider;

  /// 定位来源（双端统一）。-1=未知，0=GPS，1=网络，2=模拟，3=外设GPS，4=外设网络。见 LocationSource。
  int? locationSource;

  LocationData({
    this.code,
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.speed,
    this.bearing,
    this.address,
    this.name,
    this.timeIso,
    this.timeMs,
    this.sourceProvider,
    this.locationSource,
  });
}

/// 状态回调数据（仅 Android）。对应 TencentLocationListener.onStatusUpdate(name, status, desc)。使用 status 前请先按 name 区分设备。name 为设备名如 "GPS"、"WIFI"、"CELL"；status 为状态码，参见 SDK 状态码对照表。
class LocationStatusData {
  String? name;
  int? status;
  LocationStatusData({this.name, this.status});
}

@HostApi()
abstract class TencentLBSHostApi {
  /// SDK 初始化（方法名避免 Swift 保留字 init）。Android: TencentLocationManagerOptions.setKey + TencentLocationManager 实例及 Request 配置；iOS: TencentLBSLocationManager 配置。
  bool configure(InitOptions options);

  /// 设置用户是否同意隐私政策，调用其他接口前必须调用。对应 SDK setUserAgreePrivacy。
  void setUserAgreePrivacy(bool agree);

  /// 单次定位。Android: requestSingleFreshLocation；iOS: requestLocation。
  void requestLocationOnce();

  /// 发起连续定位。Android: requestLocationUpdates；iOS: startUpdatingLocation。androidNotificationOptions 仅 Android 后台定位时用于构建前台通知。
  void startLocationUpdates(
    ContinuousLocationRequest request,
    AndroidNotificationOptions? androidNotificationOptions,
  );

  /// 连续定位开启后可调用，更新部分参数（如定位间隔、requestLevel 等）。Android 间隔可通过 changeCallbackInterval 修改。
  void updateLocationRequest(LocationRequestUpdate? update);

  /// 停止连续定位。Android: removeUpdates；iOS: stopUpdatingLocation。
  void stopLocationUpdates();
}

@FlutterApi()
abstract class TencentLBSFlutterApi {
  void onLocation(LocationData location);
  void onError(int code, String message);
  void onStatus(LocationStatusData? status);
}
