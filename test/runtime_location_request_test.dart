import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tencent_lbs_plugin/flutter_tencent_lbs_plugin.dart';
import 'package:flutter_tencent_lbs_plugin/flutter_tencent_lbs_plugin_platform_interface.dart';
import 'package:flutter_tencent_lbs_plugin/src/flutter_tencent_lbs_plugin_pigeon_platform.dart';
import 'package:flutter_tencent_lbs_plugin/src/pigeon/location_pigeon.dart'
    as pigeon;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plugin = FlutterTencentLBSPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var failUpdate = false;
  var failOnce = false;
  final onceReplies = <Completer<List<Object?>>>[];
  const hostMethods = [
    'configure',
    'startLocationUpdates',
    'updateLocationRequest',
    'stopLocationUpdates',
    'requestLocationOnce',
  ];

  BasicMessageChannel<Object?> channel(
    String method,
  ) => BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.flutter_tencent_lbs_plugin.TencentLBSHostApi.$method',
    pigeon.TencentLBSHostApi.pigeonChannelCodec,
  );

  setUp(() async {
    calls.clear();
    failUpdate = false;
    failOnce = false;
    onceReplies.clear();
    FlutterTencentLBSPluginPlatform.instance =
        FlutterTencentLBSPluginPigeonPlatform();
    for (final method in hostMethods) {
      messenger.setMockDecodedMessageHandler<Object?>(channel(method), (
        message,
      ) async {
        calls.add(method);
        if (method == 'configure') return <Object?>[true];
        if (method == 'requestLocationOnce') {
          if (failOnce) return <Object?>['request-failed', 'SDK threw', null];
          final reply = Completer<List<Object?>>();
          onceReplies.add(reply);
          return reply.future;
        }
        if (method == 'updateLocationRequest' && failUpdate) {
          return <Object?>['location-request-failed', 'SDK rejected update', 1];
        }
        return <Object?>[null];
      });
    }
    await plugin.init(key: 'test-key');
  });

  tearDown(() {
    for (final method in hostMethods) {
      messenger.setMockDecodedMessageHandler<Object?>(channel(method), null);
    }
  });

  Future<void> sendEvent(String method, List<Object?> arguments) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      'dev.flutter.pigeon.flutter_tencent_lbs_plugin.TencentLBSFlutterApi.$method',
      pigeon.TencentLBSFlutterApi.pigeonChannelCodec.encodeMessage(arguments),
      (_) => done.complete(),
    );
    await done.future;
  }

  pigeon.LocationData position(double latitude) =>
      pigeon.LocationData(code: 0, latitude: latitude, longitude: 1);

  group('single requests', () {
    test('a host exception releases the pending request for retry', () async {
      failOnce = true;
      await expectLater(
        plugin.getLocationOnce(),
        throwsA(isA<PlatformException>()),
      );
      failOnce = false;
      final retry = plugin.getLocationOnce();
      await Future<void>.delayed(Duration.zero);
      onceReplies.single.complete([position(1)]);
      expect((await retry)?.latitude, 1);
    });

    test(
      'concurrent single requests are rejected without blocking later ones',
      () async {
        final first = plugin.getLocationOnce();
        await expectLater(plugin.getLocationOnce(), throwsStateError);
        expect(onceReplies, hasLength(1));
        onceReplies.first.complete([null]);
        expect(await first, isNull);
        final next = plugin.getLocationOnce();
        await Future<void>.delayed(Duration.zero);
        onceReplies.last.complete([position(2)]);
        expect((await next)?.latitude, 2);
      },
    );

    test(
      'single replies and continuous locations and errors stay independent',
      () async {
        final locations = <Location>[];
        final failures = <Location>[];
        plugin.addLocationListener(locations.add);
        plugin.addFailListener(failures.add);
        await plugin.getLocation(interval: 1000);
        var singleCompleted = false;
        final single = plugin.getLocationOnce().then((value) {
          singleCompleted = true;
          return value;
        });
        await sendEvent('onLocation', [position(10)]);
        await sendEvent('onError', [7, 'continuous failure']);
        expect(locations.single.latitude, 10);
        expect(failures.single.code, 7);
        expect(singleCompleted, isFalse);
        onceReplies.single.complete([position(20)]);
        expect((await single)?.latitude, 20);
        expect(locations, hasLength(1));
        expect(failures, hasLength(1));

        final failedSingle = plugin.getLocationOnce();
        await Future<void>.delayed(Duration.zero);
        onceReplies.last.complete([null]);
        expect(await failedSingle, isNull);
        expect(failures, hasLength(1));
        await sendEvent('onLocation', [position(30)]);
        expect(locations.last.latitude, 30);
      },
    );
  });

  group('runtime requests', () {
    test('a location without a result code remains a failure', () async {
      final locations = <Location>[];
      final failures = <Location>[];
      plugin.addLocationListener(locations.add);
      plugin.addFailListener(failures.add);
      await sendEvent('onLocation', [
        pigeon.LocationData(latitude: 1, longitude: 2),
      ]);
      expect(locations.single.code, 1);
      expect(failures.single, same(locations.single));
    });

    test('invalid iOS values are rejected before native calls', () async {
      for (final accuracy in [0.0, -3.0, double.nan, double.infinity]) {
        await expectLater(
          plugin.updateLocationRequest(iosDesiredAccuracy: accuracy),
          throwsArgumentError,
        );
      }
      for (final distance in [-2.0, double.nan, double.infinity]) {
        await expectLater(
          plugin.updateLocationRequest(iosDistanceFilter: distance),
          throwsArgumentError,
        );
      }
      expect(calls, ['configure']);
    });
  });

  group('optional diagnostics', () {
    test('log sink failures do not change request success or errors', () async {
      await plugin.setDebugLogging(
        enabled: true,
        onLog: (_) => throw StateError('Log sink unavailable'),
      );
      await plugin.getLocation(interval: 1000);
      await plugin.updateLocationRequest(
        locMode: TencentLBSLocMode.LOW_POWER_MODE,
      );
      failUpdate = true;
      await expectLater(
        plugin.updateLocationRequest(intervalMs: 1000),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'location-request-failed',
          ),
        ),
      );
      expect(calls.contains('stopLocationUpdates'), isFalse);
    });

    test(
      'SDK failures are logged and rethrown without losing details',
      () async {
        final received = <String>[];
        await plugin.setDebugLogging(enabled: true, onLog: received.add);
        failUpdate = true;
        await expectLater(
          plugin.updateLocationRequest(intervalMs: 30000),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.details,
              'details',
              1,
            ),
          ),
        );
        expect(received, hasLength(2));
        expect(received.last, contains('update failed:'));
        expect(received.last, contains('location-request-failed'));
        expect(received.last, contains('SDK rejected update'));
      },
    );
  });
}
