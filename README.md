# flutter_tencent_lbs_plugin

Flutter 腾讯位置服务 / 定位插件（第三方），基于腾讯定位 SDK 封装，支持单次定位、连续定位、后台定位及运行中修改定位参数。跨端通信使用 **Pigeon**，与官方 SDK 参数对齐。

---

## 注意事项

1. **iOS 模拟器**：本插件在 iOS Simulator 中不生效，需真机调试。
2. **官方文档**：各平台配置与能力以腾讯官方文档为准。  
   - [Android 定位 SDK](https://lbs.qq.com/mobile/androidLocationSDK/androidGeoGuide/androidGeoOverview)  
   - [iOS 定位 SDK](https://lbs.qq.com/mobile/iosLocationSDK/iosGeoGuide/iosGeoOverview)

---

## SDK 版本

| 平台    | 版本号   |
|---------|----------|
| Android | 7.6.1.9（Maven: `com.tencent.map.geolocation:TencentLocationSdk-openplatform`） |
| iOS     | 4.3.2（flutter_tencent_lbs_plugin/TencentLBS.xcframework） |

版本采用腾讯官方当前下载页提供的 [Android 7.6.1.9](https://lbs.qq.com/mobile/androidLocationSDK/androidGeoDownload) 和 [iOS 4.3.2](https://lbs.qq.com/mobile/iosLocationSDK/iosGeoDownload)。iOS 的 CocoaPods 与 SPM 共用上述 XCFramework。

---

## 安装

在 `pubspec.yaml` 中：

```yaml
dependencies:
  flutter_tencent_lbs_plugin: ^0.2.0  # 或 git 依赖
```

---

## 快速开始

```dart
import 'package:flutter_tencent_lbs_plugin/flutter_tencent_lbs_plugin.dart';

final plugin = FlutterTencentLBSPlugin();

// 1. 隐私协议（调用其他接口前必须调用）
plugin.setUserAgreePrivacy();

// 2. 初始化（传入腾讯地图开放平台申请的 key）
await plugin.init(key: "YOUR_KEY");

// 3. 单次定位
final location = await plugin.getLocationOnce();
print(location);  // Location(code: 0, lat: 39.9, lon: 116.4, ...)
```

### 连续定位 + 监听 + 运行中改间隔

```dart
plugin.addLocationListener((location) {
  if (location.code == 0) {
    print('位置: $location');
  }
});
plugin.addFailListener((location) {
  print('失败: ${location.code}');
});

await plugin.getLocation(
  interval: 10000,  // 10 秒
  backgroundLocation: true,
  androidNotificationOptions: AndroidNotificationOptions(
    id: 100,
    channelId: "location",
    channelName: "定位服务",
    notificationTitle: "正在定位",
  ),
);

// 运行中改为 5 秒间隔
await plugin.updateLocationRequest(intervalMs: 5000);

// 停止
plugin.stop();
```

---

## API 说明（供 Agent / 自动化参考）

### 1. 初始化 `init()`

在调用定位前调用一次；可传入与腾讯 SDK 一致的参数。

```dart
Future<bool> init({
  required String key,                    // 腾讯开放平台 apiKey，必填
  int? coordinateType,                     // 坐标系：见 TencentLBSLocationCoordinateType
  bool mockEnable = false,                 // 是否允许 Mock 定位
  int requestLevel = TencentLBSRequestLevel.AdminName,  // 结果级别
  int locMode = TencentLBSLocMode.HIGH_ACCURACY_MODE,   // 双端高精度/低功耗；仅 GPS 只支持 Android
  bool isAllowGPS = true,                 // Android：是否允许 GPS
  bool isIndoorLocationMode = false,      // Android：室内定位
  bool isGpsFirst = false,                 // Android：首次是否等卫星
  int gpsFirstTimeOut = 5000,             // Android：卫星优先超时 ms，最多 60000
}) async
```

**常用常量（`lib/model/enum.dart`）：**

- **坐标系** `TencentLBSLocationCoordinateType`：`GCJ02 = 0`（火星），`WGS84 = 1`（地球）。
- **结果级别** `TencentLBSRequestLevel`：`Geo = 0`（仅经纬度），`Name = 1`，`AdminName = 3`，`Poi = 4`。
- **定位模式** `TencentLBSLocMode`：`HIGH_ACCURACY_MODE = 10`；`LOW_POWER_MODE = 11`（兼容 `ONLY_NETWORK_MODE`）；`ONLY_GPS_MODE = 12`（仅 Android）。iOS 的 10/11 分别对应 `kCLLocationAccuracyBest` / `kCLLocationAccuracyHundredMeters`，不能指定只使用网络或 GPS；传入 12 会返回 `unsupported-mode`。
- **iOS 精度** `TencentLBSIosAccuracy`：`best = -1`、`bestForNavigation = -2`、`nearestTenMeters = 10`、`hundredMeters = 100`、`kilometer = 1000`、`threeKilometers = 3000`。数值是精度要求，不保证实际精度或关闭 GPS。

### 2. 隐私协议 `setUserAgreePrivacy()`

无参，调用其他接口前必须先调用一次。

### 3. 单次定位 `getLocationOnce()`

```dart
Future<Location?> getLocationOnce() async
```

返回 `Location?`，SDK 定位失败或 30 秒超时返回 `null`；成功时 `location.code == 0`。未初始化、同时发起多个单次请求或平台通信异常会抛出异常，异常和超时后可以重试。单次结果独立返回，不进入连续定位监听器；连续定位的回调也不会完成单次请求。

### 4. 连续定位 `getLocation()`

```dart
Future<void> getLocation({
  required int interval,                           // 回调间隔 ms，建议 ≥ 5000
  AndroidNotificationOptions? androidNotificationOptions,  // Android 前台通知，后台定位时建议传
  bool backgroundLocation = false,                  // 是否后台定位
  int? requestLevel,
  int? locMode,
  bool? allowGps,
  bool? allowCache,
  bool? gpsFirst,
  int? gpsFirstTimeOutMs,
  double? iosDesiredAccuracy,                        // iOS 精度要求，覆盖 locMode 的默认精度
  double? iosDistanceFilter,                         // iOS 最小位移，-1=不进行距离过滤
}) async
```

**Android 后台定位**：需传 `androidNotificationOptions`（通知 id、channelId、channelName、notificationTitle 等），并在 AndroidManifest 中声明前台 Service。

### 5. 运行中修改参数 `updateLocationRequest()`

连续定位已开启后可调用，仅传需要修改的字段。

```dart
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
}) async
```

更新期间保持原有定位会话和后台服务：Android 仅改间隔时调用 `changeCallbackInterval`，其余参数使用同一 listener 再次调用 `requestLocationUpdates`，不先 `removeUpdates`；iOS 原地更新 `desiredAccuracy`、`distanceFilter` 和 `requestLevel`，不调用 `stopUpdatingLocation`。

iOS 启动时关闭 SDK 的周期回调计时器（`locationCallbackInterval = 0`），由插件按 `interval` 对新定位结果节流。运行中改变间隔立即作用于后续新结果，不重启定位，也不定时重复发送旧位置；减少 GPS 耗电仍需降低精度要求。单次定位不参与此节流。

```dart
// 已经开始连续定位后，切到低功耗档。
await plugin.updateLocationRequest(
  locMode: TencentLBSLocMode.LOW_POWER_MODE,
  intervalMs: 30000,
  allowGps: false,        // Android 参数
  iosDistanceFilter: 50,
);

// 重新移动时恢复高精度。
await plugin.updateLocationRequest(
  locMode: TencentLBSLocMode.HIGH_ACCURACY_MODE,
  intervalMs: 1000,
  allowGps: true,
  iosDistanceFilter: -1,
);
```

更新失败会通过 Future 抛出 `PlatformException`；Android 保留插件中上一份成功请求，不主动停止后台服务。仅传需要变更的字段，省略字段保持当前配置；`iosDesiredAccuracy` 在同一次更新中优先于 `locMode` 的默认精度。开始前或停止后更新会返回 `not-started`。运动状态识别和自动切档由调用方决定。

SDK 文档：[Android TencentLocationManager](https://mapapi.qq.com/sdk/locationSDK/Android/doc/com/tencent/map/geolocation/TencentLocationManager.html)、[iOS TencentLBSLocationManager](https://mapapi.qq.com/sdk/locationSDK/iOS/doc/appledoc/html/Classes/TencentLBSLocationManager.html)。后台系统调度、权限变化或进程被终止仍可能影响定位，不能由参数切换接口保证永久运行。

运动状态识别与自动切档策略由宿主 App 管理，可以配合独立的运动识别插件。此插件负责运行中更新定位请求和提供切档诊断，不启动运动传感器或请求运动权限。

### 切档诊断日志（可选）

默认关闭，可在初始化前或连续定位运行中开启，不会重启定位：

```dart
await plugin.setDebugLogging(
  enabled: true,
  onLog: (message) => appLogger.info(message),
);

// 关闭日志，不影响定位。
await plugin.setDebugLogging(enabled: false);
```

日志仅在 Dart 调用边界记录连续定位启动、更新、停止的请求参数，以及原生调用的成功或异常结果。`onLog` 是可选的 `void Function(String)` 回调；未传时使用 Flutter `debugPrint`，回调异常不会中断定位。不增加原生日志通道，不逐点记录位置，也不记录 API key、经纬度或地址。日志中的成功表示原生方法返回成功，不代表已经收到定位结果。

### 6. 监听与停止

```dart
// 定位成功回调（每次收到位置都会调用）
void addLocationListener(LocationCallBack listener);   // LocationCallBack = void Function(Location location)

// 定位失败回调（如 code != 0）
void addFailListener(LocationCallBack listener);

// 状态回调（仅 Android，如 GPS/WiFi 状态变化）
void addStatusListener(LocationStatusListener listener);  // void Function(LocationStatus? status)

// 停止连续定位
void stop();
```

---

## 数据类型（导出自插件）

- **Location**：定位结果。字段：`latitude`, `longitude`, `altitude`, `horizontalAccuracy`, `verticalAccuracy`, `speed`, `bearing`, `time`, `sourceProvider`（原生原始值）, `locationSource`（双端统一）, `code`（0 为成功）。
- **LocationStatus**：状态回调数据（Android）。`name`, `status`。
- **AndroidNotificationOptions**：Android 前台通知配置。`id`, `channelId`, `channelName`, `notificationTitle`, `notificationText`, `channelDescription`, `enableVibration`, `playSound`, `showWhen`。
- **枚举类**：`TencentLBSLocationCoordinateType`, `TencentLBSRequestLevel`, `TencentLBSLocMode`, **`LocationSource`**（定位来源统一常量：`Unknown=-1`, `Gps=0`, `Network=1`, `Simulated=2`, `AccessoryGps=3`, `AccessoryNetwork=4`，iOS 与 Android SDK 返回值已映射为此统一含义）。

---

## Android 配置

### Key

通过 `plugin.init(key: "YOUR_KEY")` 传入即可。

### 权限（AndroidManifest.xml）

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_LOCATION_EXTRA_COMMANDS"/>
```

### 后台定位（前台 Service）

```xml
<application>
    <service
        android:name="com.tencent.map.geolocation.s"
        android:foregroundServiceType="location" />
</application>
```

---

## iOS 配置

### Key

通过 `plugin.init(key: "YOUR_KEY")` 传入。

### Info.plist 定位权限

至少其一：

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationAlwaysUsageDescription`

### 后台定位

- Xcode：Signing & Capabilities → + Capability → Background Modes → 勾选 **Location updates**。
- Info.plist 中 `UIBackgroundModes` 包含 `location`。

---

## 省电建议（SDK 文档）

- **定位模式**：对精度要求不高时使用 `TencentLBSLocMode.LOW_POWER_MODE`（11）。Android 使用仅网络定位；iOS 请求百米精度，由系统选择定位硬件。
- **间隔**：Android 可运行中调用原生 `changeCallbackInterval` 调整 GPS 回调频率；iOS 的插件节流减少回调处理，定位硬件节能主要通过精度和距离过滤实现。
- **allowGps**：Android 可传 `false` 减少 GPS 使用。
- **gpsFirst / gpsFirstTimeOutMs**：信号差时缩短超时或关闭“GPS 优先”，避免长时间搜星耗电。

---

## 避坑

- **地址描述**：Android 需 WGS84 才能拿到地址描述；iOS 需 GCJ02。与 SDK 默认行为一致。
- **修改插件 iOS 源文件后**：若 example 编译报“找不到已删除文件”，在 example 下执行：  
  `flutter pub get` → `cd ios` → `rm -rf Pods Podfile.lock` → `pod install`，再编译。

---

## 项目结构（供 Agent 修改/扩展时参考）

- **对外入口**：`lib/flutter_tencent_lbs_plugin.dart`，仅暴露 `FlutterTencentLBSPlugin` 与导出 model。
- **平台抽象**：`lib/flutter_tencent_lbs_plugin_platform_interface.dart`，定义接口与默认占位实现；实际实现为 Pigeon 平台。
- **Pigeon 实现**：`lib/src/flutter_tencent_lbs_plugin_pigeon_platform.dart`，实现接口并调用 Pigeon 生成 API；将 Pigeon 的 `LocationData` 转为对外 `Location`。
- **Pigeon 定义**：`pigeons/location_api.dart`。修改后需执行：  
  `dart run pigeon --input pigeons/location_api.dart`，然后执行 `dart format lib/src/pigeon/location_pigeon.dart`。
  会生成：`lib/src/pigeon/location_pigeon.dart`、Android `pigeon/LocationPigeon.kt`、iOS `ios/flutter_tencent_lbs_plugin/Sources/flutter_tencent_lbs_plugin/pigeon/LocationPigeon.swift`。**序列化格式为 List（按字段顺序），不可改为 Map；修改通信协议时应修改 pigeons 定义并重新生成，勿手改生成文件。**
- **原生层（手写）**：Android 实现位于 `android/.../pigeon/TencentLBSHostApiImpl.kt`；iOS 为 `ios/flutter_tencent_lbs_plugin/Sources/flutter_tencent_lbs_plugin/TencentLBSHostApiImpl.swift`、`FlutterTencentLbsPlugin.swift`（支持 CocoaPods + SPM 双模式），仅使用 Swift + Pigeon，无 ObjC Pigeon、无 Bridging Header。
- **请求校验与节流**：`lib/src/location_request_validation.dart` 由公开 API 和 Pigeon 平台实现共用；iOS `LocationCallbackThrottle.swift` 独立维护新回调的节流，不负责定位生命周期。
- **测试**：`test/runtime_location_request_test.dart` 分为请求行为与可选日志两组，共享 Pigeon mock；Android 请求测试和 Swift 节流测试分别验证对应原生职责。
- **已废弃**：无 MethodChannel 实现；iOS 无 ObjC Pigeon 输出；插件不再生成或依赖 `LocationCode`、Bridging Header。

---

## 参考

- [tencent_location](https://github.com/maxleexyz/tencent_location)
- [flutter_tencent_location](https://pub.dev/packages/flutter_tencent_location)
