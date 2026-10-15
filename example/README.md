# 腾讯定位插件示例

## 运行前准备

1. **申请 Key**：在 [腾讯位置服务](https://lbs.qq.com/) 申请 Android / iOS Key。
2. **配置 Key**：
   - 运行时传入 `--dart-define=TENCENT_MAP_KEY=你的Key`，示例不内置 Key。
   - Android：在 `android/app/src/main/AndroidManifest.xml` 中把 `<meta-data android:name="TencentMapSDK" android:value="YOUR KEY" />` 的 `YOUR KEY` 换成你的 Key。

## 运行

```bash
# 在仓库根目录
cd example
flutter pub get
flutter run --dart-define=TENCENT_MAP_KEY=你的Key
```

## 功能说明

- **权限**：请求定位权限。
- **单次定位**：获取一次位置并弹窗显示。
- **连续定位**：开启后按设定间隔回调；可点击「改为 2/5/10 秒」在运行中修改回调间隔。
- **停止连续定位**：停止后台定位。

## Android 构建说明

本示例的 Android 配置与 **Flutter 官方模板** 一致（Kotlin DSL）：

- **Gradle**：8.14  
- **Android Gradle Plugin**：8.11.1  
- **Kotlin**：2.2.20  

若构建报错，请先执行 `flutter clean` 再 `flutter run`。
