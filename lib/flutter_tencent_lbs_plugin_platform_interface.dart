import 'package:flutter_tencent_lbs_plugin/state/location_state.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'model/android_notification_options.dart';
import 'model/location.dart';

abstract class FlutterTencentLBSPluginPlatform extends PlatformInterface {
  FlutterTencentLBSPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  /// 默认占位，实际由 [FlutterTencentLBSPlugin] 在构造时替换为 Pigeon 实现。
  static FlutterTencentLBSPluginPlatform _instance =
      _StubFlutterTencentLBSPluginPlatform();

  static FlutterTencentLBSPluginPlatform get instance => _instance;

  static set instance(FlutterTencentLBSPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  LocationState state = LocationState();

  Future<void> setDebugLogging({
    required bool enabled,
    void Function(String message)? onLog,
  }) {
    throw UnimplementedError('setDebugLogging() has not been implemented.');
  }

  Future<bool> init({
    required String key,
    int? coordinateType,
    bool? mockEnable,
    int? requestLevel,
    int? locMode,
    bool? isAllowGPS,
    bool? isIndoorLocationMode,
    bool? isGpsFirst,
    int? gpsFirstTimeOut,
  }) {
    throw UnimplementedError('init() has not been implemented.');
  }

  void stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  Future<void> setUserAgreePrivacy() {
    throw UnimplementedError('setUserAgreePrivacy() has not been implemented.');
  }

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
  }) {
    throw UnimplementedError('getLocation() has not been implemented.');
  }

  /// 连续定位开启后可调用，更新超时时间、定位间隔等参数（与 SDK 文档一致）。
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
  }) {
    throw UnimplementedError(
      'updateLocationRequest() has not been implemented.',
    );
  }

  Future<Location?> getLocationOnce() {
    throw UnimplementedError('getLocationOnce() has not been implemented.');
  }
}

/// 占位实现，仅用于默认 instance；实际使用前会被替换为 Pigeon 实现。
class _StubFlutterTencentLBSPluginPlatform
    extends FlutterTencentLBSPluginPlatform {
  _StubFlutterTencentLBSPluginPlatform() : super();
}
