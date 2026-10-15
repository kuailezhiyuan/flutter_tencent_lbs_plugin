import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tencent_lbs_plugin/flutter_tencent_lbs_plugin_platform_interface.dart';
import 'package:flutter_tencent_lbs_plugin/model/android_notification_options.dart';
import 'package:flutter_tencent_lbs_plugin/model/location.dart';
import 'package:flutter_tencent_lbs_plugin/model/status.dart';
import 'package:flutter_tencent_lbs_plugin/src/pigeon/location_pigeon.dart'
    as pigeon;
import 'location_request_validation.dart';

/// 基于 Pigeon 的平台实现，参数与腾讯定位 SDK 文档对齐。
class FlutterTencentLBSPluginPigeonPlatform
    extends FlutterTencentLBSPluginPlatform {
  FlutterTencentLBSPluginPigeonPlatform() : super() {
    _hostApi = pigeon.TencentLBSHostApi();
    _flutterApi = _PigeonFlutterApi(this);
    pigeon.TencentLBSFlutterApi.setUp(_flutterApi);
  }

  late final pigeon.TencentLBSHostApi _hostApi;
  late final _PigeonFlutterApi _flutterApi;
  Completer<Location?>? _onceCompleter;
  bool _initialized = false;
  void Function(String message)? _logSink;

  @override
  Future<void> setDebugLogging({
    required bool enabled,
    void Function(String message)? onLog,
  }) async {
    _logSink = enabled ? (onLog ?? debugPrint) : null;
  }

  void _emitLog(String Function() message) {
    final sink = _logSink;
    if (sink == null) return;
    try {
      sink('[TencentLBS] ${message()}');
    } catch (_) {
      // Diagnostic sinks must never interrupt location or error delivery.
    }
  }

  Future<void> _traceRequest(
    String operation,
    String Function() parameters,
    Future<void> Function() send,
  ) async {
    _emitLog(() => '$operation requested: ${parameters()}');
    try {
      await send();
      _emitLog(() => '$operation succeeded');
    } catch (error) {
      _emitLog(() => '$operation failed: $error');
      rethrow;
    }
  }

  @override
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
  }) async {
    final options = pigeon.InitOptions(
      apiKey: key,
      coordinateType: coordinateType,
      mockEnable: mockEnable,
      requestLevel: requestLevel,
      locMode: locMode,
      allowGps: isAllowGPS,
      indoorLocationMode: isIndoorLocationMode,
      gpsFirst: isGpsFirst,
      gpsFirstTimeOutMs: gpsFirstTimeOut,
    );
    final ok = await _hostApi.configure(options);
    _initialized = ok;
    return ok;
  }

  @override
  Future<void> setUserAgreePrivacy() async {
    await _hostApi.setUserAgreePrivacy(true);
  }

  @override
  Future<Location?> getLocationOnce() async {
    if (!_initialized) {
      throw StateError('请先调用 init() 完成初始化');
    }
    if (_onceCompleter != null && !_onceCompleter!.isCompleted) {
      throw StateError('上一次 getLocationOnce() 仍在进行中，请等待结果后重试');
    }
    final completer = Completer<Location?>();
    _onceCompleter = completer;
    await _hostApi.requestLocationOnce();
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _onceCompleter = null;
        return null;
      },
    );
  }

  @override
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
    if (!_initialized) {
      throw StateError('请先调用 init() 完成初始化');
    }
    validateLocationRequest(
      intervalMs: interval,
      locMode: locMode,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
    final request = pigeon.ContinuousLocationRequest(
      intervalMs: interval,
      requestLevel: requestLevel,
      locMode: locMode,
      allowGps: allowGps,
      allowCache: allowCache,
      gpsFirst: gpsFirst,
      gpsFirstTimeOutMs: gpsFirstTimeOutMs,
      backgroundLocation: backgroundLocation,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
    pigeon.AndroidNotificationOptions? pigeonNotif;
    if (androidNotificationOptions != null) {
      pigeonNotif = pigeon.AndroidNotificationOptions(
        id: androidNotificationOptions.id,
        channelId: androidNotificationOptions.channelId,
        channelName: androidNotificationOptions.channelName,
        channelDescription: androidNotificationOptions.channelDescription,
        notificationTitle: androidNotificationOptions.notificationTitle,
        notificationText: androidNotificationOptions.notificationText,
        enableVibration: androidNotificationOptions.enableVibration,
        playSound: androidNotificationOptions.playSound,
        showWhen: androidNotificationOptions.showWhen,
      );
    }
    await _traceRequest(
      'start',
      () =>
          'intervalMs=$interval, mode=$locMode, allowGps=$allowGps, '
          'allowCache=$allowCache, background=$backgroundLocation, '
          'iosAccuracy=$iosDesiredAccuracy, iosDistanceFilter=$iosDistanceFilter',
      () => _hostApi.startLocationUpdates(request, pigeonNotif),
    );
  }

  @override
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
    if (!_initialized) {
      throw StateError('请先调用 init() 完成初始化');
    }
    validateLocationRequest(
      intervalMs: intervalMs,
      locMode: locMode,
      iosDesiredAccuracy: iosDesiredAccuracy,
      iosDistanceFilter: iosDistanceFilter,
    );
    final update = pigeon.LocationRequestUpdate(
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
    await _traceRequest(
      'update',
      () =>
          'intervalMs=$intervalMs, mode=$locMode, allowGps=$allowGps, '
          'allowCache=$allowCache, iosAccuracy=$iosDesiredAccuracy, '
          'iosDistanceFilter=$iosDistanceFilter',
      () => _hostApi.updateLocationRequest(update),
    );
  }

  @override
  void stop() {
    unawaited(_traceRequest('stop', () => '', _hostApi.stopLocationUpdates));
  }

  void _onLocation(pigeon.LocationData data) {
    final loc = _toLocation(data);
    if (_onceCompleter != null && !_onceCompleter!.isCompleted) {
      if ((data.code ?? 1) == 0) {
        _onceCompleter!.complete(loc);
      } else {
        _onceCompleter!.complete(null);
      }
      _onceCompleter = null;
      return;
    }
    final listeners = state.listener.toList(growable: false);
    for (final listener in listeners) {
      listener(loc);
    }
    if ((data.code ?? 1) != 0) {
      final failListeners = state.failListener.toList(growable: false);
      for (final listener in failListeners) {
        listener(loc);
      }
    }
  }

  void _onError(int code, String message) {
    final loc = Location()..code = code;
    if (_onceCompleter != null && !_onceCompleter!.isCompleted) {
      _onceCompleter!.complete(null);
      _onceCompleter = null;
      return;
    }
    final failListeners = state.failListener.toList(growable: false);
    for (final listener in failListeners) {
      listener(loc);
    }
  }

  void _onStatus(pigeon.LocationStatusData? status) {
    if (status == null) return;
    LocationStatus? res;
    if (status.status != null && status.name != null) {
      res = LocationStatus(name: status.name!, status: status.status!);
    }
    final statusListeners = state.statusListener.toList(growable: false);
    for (final listener in statusListeners) {
      listener(res);
    }
  }

  static Location _toLocation(pigeon.LocationData data) {
    final loc = Location();
    loc.code = data.code ?? 0;
    loc.latitude = data.latitude;
    loc.longitude = data.longitude;
    loc.altitude = data.altitude;
    loc.horizontalAccuracy = data.horizontalAccuracy ?? data.accuracy;
    loc.verticalAccuracy = data.verticalAccuracy;
    loc.speed = data.speed;
    loc.bearing = data.bearing;
    loc.time = data.timeMs;
    loc.sourceProvider = data.sourceProvider;
    loc.locationSource = data.locationSource;
    return loc;
  }
}

class _PigeonFlutterApi extends pigeon.TencentLBSFlutterApi {
  _PigeonFlutterApi(this._platform);

  final FlutterTencentLBSPluginPigeonPlatform _platform;

  @override
  void onLocation(pigeon.LocationData location) {
    _platform._onLocation(location);
  }

  @override
  void onError(int code, String message) {
    _platform._onError(code, message);
  }

  @override
  void onStatus(pigeon.LocationStatusData? status) {
    _platform._onStatus(status);
  }
}
