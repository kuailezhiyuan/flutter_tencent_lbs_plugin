import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
  final requests = <pigeon.ContinuousLocationRequest>[];
  final updates = <pigeon.LocationRequestUpdate>[];
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
    requests.clear();
    updates.clear();
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
        final arguments = message as List<Object?>?;
        if (method == 'configure') return <Object?>[true];
        if (method == 'requestLocationOnce') {
          if (failOnce) return <Object?>['request-failed', 'SDK threw', null];
          final reply = Completer<List<Object?>>();
          onceReplies.add(reply);
          return reply.future;
        }
        if (method == 'startLocationUpdates') {
          requests.add(arguments![0]! as pigeon.ContinuousLocationRequest);
        }
        if (method == 'updateLocationRequest') {
          updates.add(arguments![0]! as pigeon.LocationRequestUpdate);
          if (failUpdate) {
            return <Object?>[
              'location-request-failed',
              'SDK rejected update',
              1,
            ];
          }
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

    test(
      'timeout releases the request and a late reply cannot finish its successor',
      () {
        fakeAsync((clock) {
          var firstCompleted = false;
          plugin.getLocationOnce().then((value) {
            expect(value, isNull);
            firstCompleted = true;
          });
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 30));
          expect(firstCompleted, isTrue);
          var secondCompleted = false;
          plugin.getLocationOnce().then((value) {
            expect(value?.latitude, 2);
            secondCompleted = true;
          });
          clock.flushMicrotasks();
          expect(onceReplies, hasLength(2));
          onceReplies.first.complete([position(1)]);
          clock.flushMicrotasks();
          expect(secondCompleted, isFalse);
          onceReplies.last.complete([position(2)]);
          clock.flushMicrotasks();
          expect(secondCompleted, isTrue);
        });
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

    test('start forwards background and iOS settings through Pigeon', () async {
      await plugin.getLocation(
        interval: 1000,
        backgroundLocation: true,
        locMode: TencentLBSLocMode.HIGH_ACCURACY_MODE,
        iosDesiredAccuracy: TencentLBSIosAccuracy.nearestTenMeters,
        iosDistanceFilter: -1,
      );
      expect(requests.single.backgroundLocation, isTrue);
      expect(requests.single.iosDesiredAccuracy, 10);
      expect(requests.single.iosDistanceFilter, -1);
    });

    test('mode switches preserve listeners and do not call stop', () async {
      void listener(Location _) {}
      plugin.addLocationListener(listener);
      await plugin.getLocation(interval: 1000, backgroundLocation: true);
      await plugin.updateLocationRequest(
        intervalMs: 30000,
        locMode: TencentLBSLocMode.LOW_POWER_MODE,
        allowGps: false,
        iosDistanceFilter: 50,
      );
      await plugin.updateLocationRequest(
        intervalMs: 1000,
        locMode: TencentLBSLocMode.HIGH_ACCURACY_MODE,
        allowGps: true,
        iosDistanceFilter: -1,
      );
      expect(updates.first.locMode, 11);
      expect(updates.first.allowGps, isFalse);
      expect(updates.first.iosDistanceFilter, 50);
      expect(updates.last.locMode, 10);
      expect(updates.last.allowGps, isTrue);
      expect(updates.last.iosDistanceFilter, -1);
      expect(calls, [
        'configure',
        'startLocationUpdates',
        'updateLocationRequest',
        'updateLocationRequest',
      ]);
      expect(FlutterTencentLBSPluginPlatform.instance.state.listener, [
        listener,
      ]);
    });

    test('partial updates leave omitted fields null', () async {
      await plugin.updateLocationRequest(
        iosDesiredAccuracy: TencentLBSIosAccuracy.hundredMeters,
      );
      expect(updates.single.iosDesiredAccuracy, 100);
      expect(updates.single.locMode, isNull);
      expect(updates.single.intervalMs, isNull);
      expect(updates.single.iosDistanceFilter, isNull);
      expect(updates.single.allowGps, isNull);
    });

    test('SDK failures propagate and allow a later update', () async {
      failUpdate = true;
      await expectLater(
        plugin.updateLocationRequest(locMode: TencentLBSLocMode.LOW_POWER_MODE),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'location-request-failed',
          ),
        ),
      );
      failUpdate = false;
      await plugin.updateLocationRequest(
        locMode: TencentLBSLocMode.HIGH_ACCURACY_MODE,
      );
      expect(calls.contains('stopLocationUpdates'), isFalse);
      expect(updates, hasLength(2));
    });

    test(
      'invalid mode and interval are rejected before native calls',
      () async {
        await expectLater(
          plugin.updateLocationRequest(locMode: 99),
          throwsArgumentError,
        );
        await expectLater(
          plugin.updateLocationRequest(intervalMs: 999),
          throwsRangeError,
        );
        expect(updates, isEmpty);
      },
    );

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
      expect(updates, isEmpty);
    });
  });

  group('optional diagnostics', () {
    test(
      'Dart request logging is opt-in and has no native configuration',
      () async {
        final received = <String>[];
        await plugin.setDebugLogging(enabled: false, onLog: received.add);
        await plugin.getLocation(interval: 1000);
        expect(received, isEmpty);

        await plugin.setDebugLogging(enabled: true, onLog: received.add);
        await plugin.updateLocationRequest(intervalMs: 30000);
        expect(received, hasLength(2));
        expect(received.first, contains('update requested: intervalMs=30000'));
        expect(received.last, contains('update succeeded'));

        await plugin.setDebugLogging(enabled: false);
        await plugin.updateLocationRequest(intervalMs: 1000);
        expect(received, hasLength(2));
        expect(calls, [
          'configure',
          'startLocationUpdates',
          'updateLocationRequest',
          'updateLocationRequest',
        ]);
      },
    );

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
      expect(updates, hasLength(2));
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
