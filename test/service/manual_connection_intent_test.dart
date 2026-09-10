import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected preferences call: ${invocation.memberName}');
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      key == 'migrationCompleted' ? true : null;
  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async => null;
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async => null;
}

class _StopBeforeBluetooth implements Exception {}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  int stops = 0;
  bool stopBeforeBluetooth = true;
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  Future<void> stopScan() async {
    stops++;
    // Exercise the real intent/cache path, but never initiate a BLE link.
    if (stopBeforeBluetooth) throw _StopBeforeBluetooth();
  }
}

class _Link {
  bool connected = false;
  int disconnects = 0;
}

class _Device extends Fake implements BluetoothDevice {
  _Device(this.link, String id) : remoteId = DeviceIdentifier(id);
  final _Link link;
  final gate = Completer<void>();
  @override
  final DeviceIdentifier remoteId;
  @override
  bool get isConnected => link.connected;
  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 35), int? mtu = 512, bool autoConnect = false}) async {
    link.connected = true;
    await gate.future;
  }

  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    link.disconnects++;
    link.connected = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Bluetooth bluetooth;
  late ScooterService service;

  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });

  Future<void> initialize({BluetoothDevice Function(String)? deviceFactory}) async {
    bluetooth = _Bluetooth();
    service = ScooterService(bluetooth, isInBackgroundService: true, deviceFactory: deviceFactory);
    await Future<void>.delayed(Duration.zero);
    service.savedScooters = {
      'A': SavedScooter(id: 'A', name: 'Alpha', color: 1),
      'B': SavedScooter(id: 'B', name: 'Beta', color: 2),
    };
    addTearDown(service.dispose);
  }

  test('a superseded selection cannot publish its connecting row or cache', () async {
    await initialize();
    final publishedTargets = <String>[];
    service.addListener(() {
      final target = service.connectingScooterId;
      if (target != null) publishedTargets.add(target);
    });
    final first = service.connectToScooterId('A');
    final second = service.connectToScooterId('B');
    final stopped = expectLater(second, throwsA(isA<_StopBeforeBluetooth>()));
    await first;
    await stopped;
    expect(bluetooth.stops, 1);
    expect(publishedTargets, isNotEmpty);
    expect(publishedTargets, everyElement('B'));
    expect(service.identity.name, 'Beta');
  });

  test('selecting another scooter immediately clears the live odometer', () async {
    await initialize();
    service.identity.odometerMeters = 123400;
    await expectLater(service.connectToScooterId('B'), throwsA(isA<_StopBeforeBluetooth>()));
    expect(service.identity.odometerMeters, isNull);
    expect(service.identity.name, 'Beta');
  });

  test('stale failure cannot disconnect a newer attempt using the same device ID', () async {
    final link = _Link();
    final devices = <_Device>[];
    await initialize(deviceFactory: (id) {
      final device = _Device(link, id);
      devices.add(device);
      return device;
    });
    bluetooth.stopBeforeBluetooth = false;
    final first = service.connectToScooterId('A');
    final firstFailure = expectLater(first, throwsA(isA<_StopBeforeBluetooth>()));
    await Future<void>.delayed(Duration.zero);
    final second = service.connectToScooterId('A');
    final secondFailure = expectLater(second, throwsA(isA<_StopBeforeBluetooth>()));
    await Future<void>.delayed(Duration.zero);
    expect(devices, hasLength(2));
    devices.first.gate.completeError(_StopBeforeBluetooth());
    await firstFailure;
    final connectedAfterStaleFailure = link.connected;
    final disconnectsAfterStaleFailure = link.disconnects;
    // The current attempt's own failure must, conversely, clean up its link.
    devices.last.gate.completeError(_StopBeforeBluetooth());
    await secondFailure;
    expect(connectedAfterStaleFailure, isTrue);
    expect(disconnectsAfterStaleFailure, 0);
    expect(link.connected, isFalse);
    expect(link.disconnects, 1);
  });

  test('failed manual selection stays pinned against generic startup', () async {
    await initialize();
    await expectLater(service.connectToScooterId('B'), throwsA(isA<_StopBeforeBluetooth>()));
    // The fake has no adapter or scan implementation: falling through into
    // generic startup would fail rather than silently contact another scooter.
    service.start();
    await Future<void>.delayed(Duration.zero);
    expect(bluetooth.stops, 1);
    expect(service.identity.name, 'Beta');
  });
}
