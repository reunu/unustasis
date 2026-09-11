import 'dart:async';

// Same virtual timer harness as the imported real-service regressions.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:unustasis/background/bg_service.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('$invocation');
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => null;
  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async => null;
}

class _Storage extends Fake implements ScooterStorage {
  @override
  Map<String, SavedScooter> scooters = {};
  int selections = 0;
  SavedScooter? recent;
  @override
  SavedScooter? getMostRecent() {
    selections++;
    return recent;
  }
  @override
  Future<void> load() async {}
}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  Future<void> stopScan() async {}
}

class _Device extends Fake implements BluetoothDevice {
  @override
  DeviceIdentifier get remoteId => const DeviceIdentifier('A');
  @override
  bool get isConnected => false;
  @override
  bool get isDisconnected => true;
  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 35),
      int? mtu = 512, bool autoConnect = false}) => Completer<void>().future;
  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesAsyncPlatform? previousPreferences;
  late RecordingBackgroundService messages;
  setUp(() {
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    FlutterBackgroundServicePlatform.instance = messages = RecordingBackgroundService();
    SharedPreferencesAsyncPlatform.instance = _Preferences();
  });
  tearDown(() {
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
  });

  test('foreground intent publishes legacy metadata, heartbeat at 60s and explicit release', () {
    fakeAsync((time) {
      final storage = _Storage();
      final service = ScooterService(_Bluetooth(), storage: storage, deviceFromId: (_) => _Device());
      time.flushMicrotasks();
      storage.scooters['A'] = SavedScooter(id: 'A', name: 'Unu', color: 2);
      messages.updates.clear();
      unawaited(service.connectToScooterId('A'));
      time.flushMicrotasks();
      final updates = messages.updates.where((m) => (m['args'] as Map?)?.containsKey('manualConnectionTarget') == true).toList();
      expect(updates.first['args'], {
        'manualConnectionTarget': 'A', 'scooterName': 'Unu', 'scooterColor': 2,
      });
      messages.updates.clear();
      time.elapse(const Duration(seconds: 59));
      expect(messages.updates, isEmpty);
      time.elapse(const Duration(seconds: 1));
      expect(messages.updates.single['args'], {'manualConnectionTarget': 'A'});
      service.stopAutoRestart();
      expect(messages.updates.last['args'], {'manualConnectionTarget': ''});
      messages.updates.clear();
      time.elapse(const Duration(seconds: 60));
      expect(messages.updates, isEmpty);
      service.dispose();
      expect(time.periodicTimerCount, 0);
    });
  });

  test('background consumer suppresses selection, touches on legacy metadata, expires at five minutes', () async {
    // Frozen shared runtime uses DateTime.now, which fakeAsync cannot virtualize.
    // Wall-time deadlines match that policy; monotonic time bounds backward steps.
    final elapsed = Stopwatch()..start();
    final storage = _Storage();
    final service = ScooterService(_Bluetooth(), storage: storage,
        isInBackgroundService: true, initializeRuntime: false);
    addTearDown(service.dispose);
    final armedBefore = DateTime.now();
    handleForegroundConnectionUpdate(service, {'manualConnectionTarget': 'A'});
    final armedAfter = DateTime.now();
    expect(await service.attemptLatestAutoConnection(), isFalse);
    expect(storage.selections, 0);
    await Future<void>.delayed(const Duration(minutes: 4));
    final touchedBefore = DateTime.now();
    handleForegroundConnectionUpdate(service, {'scooterName': 'Unu', 'scooterColor': 2});
    final touchedAfter = DateTime.now();
    final touchedElapsed = elapsed.elapsed;
    // ignore: avoid_print
    print('Arm wall: $armedBefore .. $armedAfter; touch wall: $touchedBefore .. $touchedAfter; monotonic: $touchedElapsed');
    await Future<void>.delayed(const Duration(minutes: 4, seconds: 59));
    final insideWindow = DateTime.now();
    // ignore: avoid_print
    print('Pre-expiry wall: $insideWindow; since touch: ${insideWindow.difference(touchedAfter)}; monotonic: ${elapsed.elapsed - touchedElapsed}');
    // The initial arm would have expired, but the legacy metadata touch has not.
    expect(insideWindow.isAfter(armedAfter.add(const Duration(minutes: 5))), isTrue);
    expect(insideWindow.isBefore(touchedBefore.add(const Duration(minutes: 5))), isTrue);
    await service.attemptLatestAutoConnection();
    expect(storage.selections, 0);
    // DateTime and Stopwatch can advance differently. Do not check the wall-clock
    // gate until after the latest possible captured touch time plus its policy.
    final deadline = touchedAfter.add(const Duration(minutes: 5, milliseconds: 100));
    while (DateTime.now().isBefore(deadline)) {
      expect(elapsed.elapsed, lessThan(const Duration(minutes: 11)),
          reason: 'Wall time did not reach expiry within the monotonic bound');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final expiredAt = DateTime.now();
    // ignore: avoid_print
    print('Expiry wall: $expiredAt; since touch: ${expiredAt.difference(touchedAfter)}; monotonic: ${elapsed.elapsed - touchedElapsed}');
    expect(expiredAt.isBefore(deadline), isFalse);
    await service.attemptLatestAutoConnection();
    expect(storage.selections, 1);
    expect(messages.updates, isEmpty, reason: 'Background must not relay UI messages');
  }, timeout: const Timeout(Duration(minutes: 12)));

  test('manual target arriving during candidate selection prevents connection', () async {
    final storage = _Storage()..recent = SavedScooter(id: 'B');
    final devices = <String>[];
    final service = ScooterService(_Bluetooth(), storage: storage,
        initializeRuntime: false, isInBackgroundService: true,
        deviceFromId: (id) { devices.add(id); return _Device(); });
    addTearDown(service.dispose);
    final attempt = service.attemptLatestAutoConnection();
    handleForegroundConnectionUpdate(service, {'manualConnectionTarget': 'A'});
    // The pin arrives during runtime's awaited most-recent selection.
    expect(await attempt, isFalse);
    expect(storage.selections, 1);
    expect(devices, isEmpty);
    expect(service.connectingScooterId, isNull);
    expect(service.myScooter, isNull);
  });

  test('empty and null targets release; legacy-only metadata does not arm suppression', () async {
    final storage = _Storage();
    final service = ScooterService(_Bluetooth(), storage: storage,
        isInBackgroundService: true, initializeRuntime: false);
    addTearDown(service.dispose);
    for (final clear in ['', null]) {
      handleForegroundConnectionUpdate(service, {'manualConnectionTarget': 'A'});
      handleForegroundConnectionUpdate(service, {'manualConnectionTarget': clear});
      await service.attemptLatestAutoConnection();
    }
    handleForegroundConnectionUpdate(service, {'scooterName': 'Unu'});
    await service.attemptLatestAutoConnection();
    expect(storage.selections, 3);
  });
}
