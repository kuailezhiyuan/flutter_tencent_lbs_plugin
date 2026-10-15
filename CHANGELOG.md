## Unreleased

- 腾讯定位 SDK 更新至 Android 7.6.1.9、iOS 4.3.2；Pigeon 更新至 29.0.10，并重新生成三端通信代码。
- 单次定位通过独立请求返回结果，避免与连续定位事件混淆；请求异常和超时后允许重试，迟到结果不会影响下一次请求。
- Android 后台通知配置无效时，启动请求直接返回异常。
- 定位进行中拒绝重新初始化；引擎解绑时停止定位、取消待完成单次请求并释放回调。
- 清除重复的 Android 通知数据类和闲置 Gradle 脚本，保留通知行为；示例通过运行参数接收 Key，并正确处理异步失败和退出清理。
- 增加可选的 Dart 字符串日志回调，可接入 App 日志或默认使用 Flutter debugPrint；仅记录定位请求、成功和异常，不增加原生日志通道。
- Android 运行中切换请求时保留 listener 和前台服务，不再先移除定位监听；检查 SDK 注册返回码并保留上一份成功请求。
- iOS 支持高精度/低功耗模式及显式精度、距离过滤参数，运行中更新不停止定位。
- iOS 对新结果进行可动态调整的回调节流，避免重启 SDK 的周期计时器及重复分发旧位置。

## 0.2.0

- Android SDK 升级至 7.6.1.8
- iOS SDK 升级至 4.3.1（新增地理围栏功能）
- iOS 切换到 xcframework，支持 Apple Silicon 模拟器（与 SPM 同路径，仅保留一份）
- iOS 添加 Swift Package Manager 支持（兼容 CocoaPods + SPM 双模式）
- Android 移除 Kotlin Gradle Plugin，改用 Flutter 内置 Kotlin
- Java/Kotlin target 升级至 JDK 17

## 0.1.0

🐞 fix: 修复安装插件后 App 无法在 iOS Simulator 启动的 bug


## 0.0.1

### TencentLBS 版本

| 平台    | 版本号   | 时间       |
| ------- | -------- | ---------- |
| Android | v7.5.4.3 | 2024-01-23 |
| iOS     | v4.2.0   | 2023-11-03 |
