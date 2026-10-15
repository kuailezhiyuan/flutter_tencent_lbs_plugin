import '../model/enum.dart';

void validateLocationRequest({
  int? intervalMs,
  int? locMode,
  double? iosDesiredAccuracy,
  double? iosDistanceFilter,
}) {
  if (intervalMs != null && intervalMs < 1000) {
    throw RangeError.value(intervalMs, 'intervalMs', '必须大于等于 1000 毫秒');
  }
  if (locMode != null &&
      locMode != TencentLBSLocMode.HIGH_ACCURACY_MODE &&
      locMode != TencentLBSLocMode.LOW_POWER_MODE &&
      locMode != TencentLBSLocMode.ONLY_GPS_MODE) {
    throw ArgumentError.value(locMode, 'locMode', '必须为 10、11 或 12');
  }
  if (iosDesiredAccuracy != null &&
      (!iosDesiredAccuracy.isFinite ||
          !(iosDesiredAccuracy > 0 ||
              iosDesiredAccuracy == TencentLBSIosAccuracy.best ||
              iosDesiredAccuracy == TencentLBSIosAccuracy.bestForNavigation))) {
    throw ArgumentError.value(
      iosDesiredAccuracy,
      'iosDesiredAccuracy',
      '必须为正数、best (-1) 或 bestForNavigation (-2)',
    );
  }
  if (iosDistanceFilter != null &&
      (!iosDistanceFilter.isFinite ||
          !(iosDistanceFilter >= 0 || iosDistanceFilter == -1))) {
    throw ArgumentError.value(
      iosDistanceFilter,
      'iosDistanceFilter',
      '必须为非负数或 -1（不进行距离过滤）',
    );
  }
}
