import 'package:flutter/material.dart';

import 'package:flutter_tencent_lbs_plugin/flutter_tencent_lbs_plugin.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const Root());
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: MainApp()),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final locationPlugin = FlutterTencentLBSPlugin();

  /// 是否已开启连续定位
  bool _isContinuousRunning = false;
  /// 当前定位回调间隔（毫秒）
  int _currentIntervalMs = 5000;
  /// 最近一次定位结果（用于界面展示）
  Location? _lastLocation;
  /// 最近一次定位时间
  DateTime? _lastUpdateTime;
  String? _lastError;
  /// 是否已完成初始化（init 已 await 完成）
  bool _pluginReady = false;

  void _onLocation(Location location) {
    if (location.code == 0) {
      if (mounted) {
        setState(() {
          _lastLocation = location;
          _lastUpdateTime = DateTime.now();
          _lastError = null;
        });
      }
      print("[[ listener ]]: $location");
    }
  }

  void _onFail(Location location) {
    if (mounted) {
      setState(() => _lastError = "code: ${location.code}");
    }
    print("[[ fail ]]: ${location.code}");
  }

  @override
  void initState() {
    super.initState();
    _initAndRegister();
  }

  /// 先 await 隐私同意与 init 完成再注册监听，避免竞态
  Future<void> _initAndRegister() async {
    try {
      await locationPlugin.setUserAgreePrivacy();
      await locationPlugin.init(key: "TFKBZ-FFLA4-UU7U6-FCROC-TOFSH-AEBIM");
    } catch (err) {
      if (!mounted) return;
      setState(() => _lastError = '初始化失败: $err');
      return;
    }
    if (!mounted) return;
    locationPlugin.addLocationListener(_onLocation);
    locationPlugin.addFailListener(_onFail);
    setState(() => _pluginReady = true);
  }

  @override
  void dispose() {
    locationPlugin.removeLocationListener(_onLocation);
    locationPlugin.removeFailListener(_onFail);
    super.dispose();
  }

  void _startContinuousLocation() {
    locationPlugin.getLocation(
      interval: _currentIntervalMs,
      backgroundLocation: true,
      androidNotificationOptions: AndroidNotificationOptions(
        id: 100,
        channelId: "100",
        channelName: "定位常驻通知",
        notificationTitle: "定位常驻通知标题文字",
        notificationText: "定位常驻通知内容文字",
      ),
    );
    setState(() => _isContinuousRunning = true);
  }

  void _stopContinuousLocation() {
    locationPlugin.stop();
    setState(() => _isContinuousRunning = false);
  }

  /// 连续定位开启后，动态修改定位间隔等参数
  Future<void> _updateInterval(int newIntervalMs) async {
    if (!_isContinuousRunning) return;
    await locationPlugin.updateLocationRequest(intervalMs: newIntervalMs);
    setState(() => _currentIntervalMs = newIntervalMs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已改为 ${newIntervalMs ~/ 1000} 秒回调一次')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '腾讯定位 Demo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '请将 init(key: "YOUR KEY") 替换为你在腾讯位置服务申请的 Key',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (!_pluginReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('初始化中…', style: TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            const SizedBox(height: 24),

            // 权限
            const Divider(height: 32),
            const Text('权限', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Permission.location.request(),
              child: const Text('请求定位权限'),
            ),

            // 单次定位
            const Divider(height: 32),
            const Text('单次定位', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _pluginReady
                  ? () {
                      locationPlugin.getLocationOnce().then((value) {
                        print("[[ getLocationOnce ]]: $value");
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: Text(
                              value != null
                                  ? "经度: ${value.longitude?.toStringAsFixed(6)}\n纬度: ${value.latitude?.toStringAsFixed(6)}"
                                  : "定位失败",
                            ),
                          ),
                        );
                      }).catchError((err) {
                        print("[[ getLocationOnce ERROR ]]: $err");
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('失败: $err')),
                        );
                      });
                    }
                  : null,
              child: const Text('获取一次定位'),
            ),

            // 连续定位
            const Divider(height: 32),
            const Text('连续定位', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _pluginReady && !_isContinuousRunning ? _startContinuousLocation : null,
              child: Text(_isContinuousRunning ? '连续定位已开启' : '开启连续定位 (${_currentIntervalMs ~/ 1000}s 间隔)'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isContinuousRunning ? _stopContinuousLocation : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('停止连续定位'),
            ),

            // 连续定位中修改参数（仅开启后可用）
            if (_isContinuousRunning) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '连续定位中修改参数',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '当前回调间隔: ${_currentIntervalMs ~/ 1000} 秒',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _updateInterval(2000),
                            child: const Text('改为 2 秒'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _updateInterval(5000),
                            child: const Text('改为 5 秒'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _updateInterval(10000),
                            child: const Text('改为 10 秒'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 最近一次位置
            const Divider(height: 32),
            const Text('最近一次位置', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _lastLocation != null && _lastLocation!.code == 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('经度: ${_lastLocation!.longitude?.toStringAsFixed(6) ?? "—"}'),
                          Text('纬度: ${_lastLocation!.latitude?.toStringAsFixed(6) ?? "—"}'),
                          if (_lastUpdateTime != null)
                            Text(
                              '时间: $_lastUpdateTime',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      )
                    : Text(
                        _lastError ?? '暂无定位结果（可先开启连续定位或单次定位）',
                        style: TextStyle(
                          fontSize: 13,
                          color: _lastError != null ? Colors.red : Colors.grey,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
