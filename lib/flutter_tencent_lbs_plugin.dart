import 'package:flutter_tencent_lbs_plugin/model/enum.dart';

import 'flutter_tencent_lbs_plugin_platform_interface.dart';
import 'model/android_notification_options.dart';
import 'model/location.dart';
import 'state/location_state.dart';
import 'src/flutter_tencent_lbs_plugin_pigeon_platform.dart';
import 'src/location_request_validation.dart';

export 'model/android_notification_options.dart';
export 'model/enum.dart';
export 'model/location.dart';
export 'model/status.dart';

class FlutterTencentLBSPlugin {
  static bool _pigeonRegistered = false;
  static void _ensurePigeon() {
    if (_pigeonRegistered) return;
    _pigeonRegistered = true;
    FlutterTencentLBSPluginPlatform.instance =
        FlutterTencentLBSPluginPigeonPlatform();
  }

  FlutterTencentLBSPlugin() {
    _ensurePigeon();
  }

  /// 开关 Dart 定位请求日志，可在初始化前或定位运行中调用，不重启定位。
  /// 默认关闭；未传 [onLog] 时输出到 Flutter 控制台。
  /// 只记录启动、停止、请求变更及调用结果，不逐点记录位置。
  /// 传入回调可将日志接入 App 的日志文件。回调异常不会打断定位。
  Future<void> setDebugLogging({
    required bool enabled,
    void Function(String message)? onLog,
  }) {
    return FlutterTencentLBSPluginPlatform.instance.setDebugLogging(
      enabled: enabled,
      onLog: onLog,
    );
  }

  /// 初始化 SDK。
  ///
  /// 调用成功后才可继续调用 [getLocationOnce]、[getLocation] 等定位接口。
  Future<bool> init({
    /// 申请的 apiKey
    required String key,

    /// 经纬度坐标类型：0=GCJ02(火星), 1=WGS84(地球)，与 SDK 文档一致
    int? coordinateType,

    /// 设置是否允许 MockGPS
    bool mockEnable = false,

    /// 定位结果信息级别：0=GEO, 1=NAME, 3=ADMIN_AREA, 4=POI，与 TencentLocationRequest.requestLevel 一致
    int requestLevel = TencentLBSRequestLevel.AdminName,

    /// 双端：10=高精度、11=低功耗；12=仅 GPS（只支持 Android）。
    int locMode = TencentLBSLocMode.HIGH_ACCURACY_MODE,

    /// Android：是否允许使用 GPS
    bool isAllowGPS = true,

    /// Android：是否开启室内定位
    bool isIndoorLocationMode = false,

    /// Android：首次定位是否等待卫星结果
    bool isGpsFirst = false,

    /// Android：卫星优先时的超时时间 ms，最多 60000
    int gpsFirstTimeOut = 5000,
  }) async {
    validateLocationRequest(locMode: locMode);
    return await FlutterTencentLBSPluginPlatform.instance.init(
      key: key,
      coordinateType: coordinateType ?? TencentLBSLocationCoordinateType.WGS84,
      mockEnable: mockEnable,
      requestLevel: requestLevel,
      locMode: locMode,
      isAllowGPS: isAllowGPS,
      isIndoorLocationMode: isIndoorLocationMode,
      isGpsFirst: isGpsFirst,
      gpsFirstTimeOut: gpsFirstTimeOut,
    );
  }

  /// 设置用户是否同意隐私协议。
  Future<void> setUserAgreePrivacy() async {
    await FlutterTencentLBSPluginPlatform.instance.setUserAgreePrivacy();
  }

  /// 发起单次定位请求。
  ///
  /// 成功返回 [Location]；SDK 定位失败或 30 秒超时返回 `null`。
  /// 未初始化、并发单次请求或平台通信异常会抛出异常，之后可重试。
  /// 单次结果不进入连续定位监听器。
  Future<Location?> getLocationOnce() async {
    return await FlutterTencentLBSPluginPlatform.instance.getLocationOnce();
  }

  /// 开启连续定位（参数与 SDK 一致）。
  ///
  /// [interval] 单位毫秒，严格要求 `>= 1000`，否则抛 [RangeError]。
  /// 当 [backgroundLocation] 为 `true` 时，Android 需传 [androidNotificationOptions]。
  Future<void> getLocation({
    required int interval,
    AndroidNotificationOptions? androidNotificationOptions,
    bool backgroundLocation = false,
    int? requestLevel,
    int? locMode,
    bool? allowGps,
    bool? allowCache,
    bool? gpsFirst,
    int? gpsFirstTimeOutMs,
    double? iosDesiredAccuracy,
    double? iosDistanceFilter,
  }) async {
    validateLocationRequest(
      intervalMs: interval,
      locMode: locMode,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
    return await FlutterTencentLBSPluginPlatform.instance.getLocation(
      interval: interval,
      androidNotificationOptions: androidNotificationOptions,
      backgroundLocation: backgroundLocation,
      requestLevel: requestLevel,
      locMode: locMode,
      allowGps: allowGps,
      allowCache: allowCache,
      gpsFirst: gpsFirst,
      gpsFirstTimeOutMs: gpsFirstTimeOutMs,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
  }

  /// 连续定位开启后，动态更新请求参数。
  ///
  /// 仅需传要变更的字段；[intervalMs] 若传入则必须 `>= 1000`，否则抛 [RangeError]。
  /// 双端切换不主动停止定位或后台服务。iOS 的模式对应精度要求；
  /// [iosDesiredAccuracy] 可覆盖模式的默认精度，[iosDistanceFilter] 单位米。
  /// iOS 的间隔由插件对新定位回调节流，不会定时重复发送缓存位置。
  Future<void> updateLocationRequest({
    int? intervalMs,
    int? requestLevel,
    int? locMode,
    int? gpsFirstTimeOutMs,
    bool? allowGps,
    bool? allowCache,
    bool? gpsFirst,
    double? iosDesiredAccuracy,
    double? iosDistanceFilter,
  }) async {
    validateLocationRequest(
      intervalMs: intervalMs,
      locMode: locMode,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
    return await FlutterTencentLBSPluginPlatform.instance.updateLocationRequest(
      intervalMs: intervalMs,
      requestLevel: requestLevel,
      locMode: locMode,
      gpsFirstTimeOutMs: gpsFirstTimeOutMs,
      allowGps: allowGps,
      allowCache: allowCache,
      gpsFirst: gpsFirst,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
  }

  /// 添加状态回调（仅 Android）。
  void addStatusListener(LocationStatusListener listener) {
    FlutterTencentLBSPluginPlatform.instance.state.statusListener.add(listener);
  }

  /// 添加定位失败回调。
  void addFailListener(LocationCallBack listener) {
    FlutterTencentLBSPluginPlatform.instance.state.failListener.add(listener);
  }

  /// 添加定位成功回调。
  void addLocationListener(LocationCallBack listener) {
    FlutterTencentLBSPluginPlatform.instance.state.listener.add(listener);
  }

  /// 移除定位成功回调（需传入与 [addLocationListener] 相同的引用）
  void removeLocationListener(LocationCallBack listener) {
    FlutterTencentLBSPluginPlatform.instance.state.listener.remove(listener);
  }

  /// 移除定位失败回调（需传入与 [addFailListener] 相同的引用）
  void removeFailListener(LocationCallBack listener) {
    FlutterTencentLBSPluginPlatform.instance.state.failListener.remove(
      listener,
    );
  }

  /// 移除状态回调（需传入与 [addStatusListener] 相同的引用）
  void removeStatusListener(LocationStatusListener listener) {
    FlutterTencentLBSPluginPlatform.instance.state.statusListener.remove(
      listener,
    );
  }

  /// 停止连续定位。
  void stop() {
    FlutterTencentLBSPluginPlatform.instance.stop();
  }
}
