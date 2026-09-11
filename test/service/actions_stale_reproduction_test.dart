import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:unustasis/domain/statistics_helper.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

class _Storage extends Fake implements ScooterStorage {
  @override
  Map<String, SavedScooter> scooters = {
    'A': SavedScooter(id: 'A', name: 'Alpha', color: 1),
    'B': SavedScooter(id: 'B', name: 'Beta', color: 2),
  };
  int loads = 0;
  final List<String> additions = [];
  final List<String> pings = [];
  final List<String> removals = [];
  Completer<void>? removeGate;
  Completer<void>? loadGate;

  @override
  Future<void> remove(String id) async {
    removals.add(id);
    await removeGate?.future;
    scooters.remove(id);
  }

  @override
  SavedScooter? getMostRecent() => scooters.values.firstOrNull;

  @override
  void updatePing(String id) {
    pings.add(id);
    scooters[id]?.lastPing = DateTime.now();
  }

  @override
  Future<void> load() async {
    loads++;
    await loadGate?.future;
  }

  @override
  Future<bool> add(String id) async {
    additions.add(id);
    return false; // Both test scooters are already saved; no plugin writes.
  }
}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  int stops = 0;
  int scanStreamReads = 0;

  @override
  Stream<bool> get isScanning {
    scanStreamReads++;
    throw StateError('Runtime-disabled services must not subscribe to scanning');
  }

  @override
  Future<void> stopScan() async {
    stops++;
  }
}

// Wrappers for the same remote ID share the underlying physical link.
class _Transport {
  bool linked = false;
  int disconnects = 0;
}

class _Device extends Fake implements BluetoothDevice {
  _Device(String id, [_Transport? transport])
      : remoteId = DeviceIdentifier(id),
        transport = transport ?? _Transport();
  final _Transport transport;
  @override
  final DeviceIdentifier remoteId;
  final List<Completer<void>> connections = [Completer<void>()];
  Completer<void> get connection => connections.first;
  final List<Duration> timeouts = [];
  bool get linked => transport.linked;
  set linked(bool value) => transport.linked = value;
  int disconnects = 0;
  int bondRemovals = 0;
  Completer<void>? disconnectGate;
  Completer<void>? bondGate;
  @override
  Future<void> removeBond({int timeout = 30}) async {
    bondRemovals++;
    await bondGate?.future;
  }

  int listens = 0;
  int cancels = 0;
  late final states = StreamController<BluetoothConnectionState>.broadcast(
    onListen: () => listens++,
    onCancel: () => cancels++,
  );
  @override
  Stream<BluetoothConnectionState> get connectionState => states.stream;
  @override
  DisconnectReason? get disconnectReason => null;

  void emitDisconnected() {
    linked = false;
    states.add(BluetoothConnectionState.disconnected);
  }

  @override
  bool get isConnected => linked;
  @override
  bool get isDisconnected => !linked;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    final index = timeouts.length;
    if (index == connections.length) connections.add(Completer<void>());
    timeouts.add(timeout);
    await connections[index].future;
    linked = true;
  }

  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    disconnects++;
    transport.disconnects++;
    await disconnectGate?.future;
    linked = false;
  }
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic(this.bytes);
  final List<int> bytes;
  final values = StreamController<List<int>>.broadcast();
  int reads = 0;
  int notifications = 0;
  final writes = <String>[];
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    writes.add(String.fromCharCodes(value));
  }

  @override
  Stream<List<int>> get lastValueStream => values.stream;
  @override
  Stream<List<int>> get onValueReceived => values.stream;
  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) async {
    notifications++;
    return true;
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    reads++;
    values.add(bytes);
    return bytes;
  }
}

class _Repository extends CharacteristicRepository {
  _Repository() : super(_Device('repository-only')) {
    commandCharacteristic = characteristic([]);
    hibernationCommandCharacteristic = null;
    stateCharacteristic = characteristic('parked'.codeUnits);
    powerStateCharacteristic = characteristic('running'.codeUnits);
    seatCharacteristic = characteristic('closed'.codeUnits);
    handlebarCharacteristic = characteristic('locked'.codeUnits);
    auxSOCCharacteristic = characteristic([70, 0, 0, 0]);
    auxVoltageCharacteristic = characteristic([0, 0, 0, 0]);
    auxChargingCharacteristic = characteristic('not-charging'.codeUnits);
    cbbSOCCharacteristic = characteristic([80]);
    cbbVoltageCharacteristic = characteristic([0, 0, 0, 0]);
    cbbCapacityCharacteristic = characteristic([0, 0, 0, 0]);
    cbbChargingCharacteristic = characteristic('not-charging'.codeUnits);
    cbbFullCapacityCharacteristic = null;
    primaryStateCharacteristic = null;
    primaryPresentCharacteristic = null;
    primaryCyclesCharacteristic = characteristic([1, 0, 0, 0]);
    primarySOCCharacteristic = characteristic([90, 0, 0, 0]);
    secondaryCyclesCharacteristic = characteristic([2, 0, 0, 0]);
    secondarySOCCharacteristic = characteristic([60, 0, 0, 0]);
    nrfVersionCharacteristic = characteristic('test-firmware'.codeUnits);
    imxVersionCharacteristic = null;
    odometerCharacteristic = characteristic([123, 0, 0, 0]);
    systemTimeCharacteristic = null;
    navigationActiveCharacteristic = null;
    umsStatusCharacteristic = null;
    extendedCommandCharacteristic = null;
    extendedResponseCharacteristic = null;
  }
  final characteristics = <_Characteristic>[];
  _Characteristic characteristic(List<int> value) {
    final result = _Characteristic(value);
    characteristics.add(result);
    return result;
  }

  int completenessChecks = 0;
  @override
  bool anyAreNull() {
    completenessChecks++;
    return super.anyAreNull();
  }

  final Completer<void> discovery = Completer<void>();
  final List<bool> requests = [];

  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) {
    requests.add(additionalLibrescootFeatures);
    return discovery.future;
  }
}

class _Service extends ScooterService {
  _Service(super.flutterBluePlus, _Storage storage, Map<String, _Device> devices, List<String> deviceRequests,
      _Repository repository, List<BluetoothDevice> repositories,
      {Future<LatLng?> Function()? pollLocation})
      : super(
          pollLocation: pollLocation ?? (() async => null),
          storage: storage,
          initializeRuntime: false,
          deviceFromId: (id) {
            deviceRequests.add(id);
            return devices[id]!;
          },
          repositoryFactory: (device) {
            repositories.add(device);
            return repository;
          },
        );

  final List<Map<String, dynamic>> updates = [];
  @override
  void updateBackgroundService(dynamic data) {
    updates.add(Map<String, dynamic>.from(data as Map));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
  });
  test('pending same-ID reconnect cannot publish into a forget already awaiting old disconnect', () async {
    final old = _Device('A')..connection.complete();
    final replacement = _Device('A');
    final devices = {'A': old};
    final storage = _Storage();
    final repo = _Repository()..discovery.complete();
    final service = _Service(_Bluetooth(), storage, devices, [], repo, []);
    addTearDown(service.dispose);
    await service.connectToScooterId('A');
    old.emitDisconnected();
    await Future<void>.delayed(Duration.zero);
    devices['A'] = replacement;
    final reconnecting = service.connectToScooterId('A');
    await Future<void>.delayed(Duration.zero);
    expect(replacement.timeouts.length, 1);
    old.disconnectGate = Completer<void>();
    final forgetting = service.forgetSavedScooter('A');
    await Future<void>.delayed(Duration.zero);
    replacement.connection.complete();
    await reconnecting;
    old.disconnectGate!.complete();
    await forgetting;
    expect(storage.removals, isEmpty);
    expect(service.myScooter, same(replacement));
    expect(service.connected, true);
    expect(old.disconnects, 0);
    expect(old.bondRemovals, 0);
    expect(replacement.disconnects, 0);
    expect(replacement.bondRemovals, 0);
  });
  for (final entry in ['saved-A', 'saved-B', 'shared']) {
    for (final automatic in [false, true]) {
      for (final pendingId in ['A', 'B']) {
        for (final succeeds in [false, true]) {
          test(
              '$entry defers during ${automatic ? 'automatic' : 'manual'} pending $pendingId then forgets after ${succeeds ? 'success' : 'failure'}',
              () async {
            final old = _Device('A')..connection.complete();
            final pending = _Device(pendingId);
            final devices = {'A': old, 'B': _Device('B')};
            final storage = _Storage();
            final repo = _Repository()..discovery.complete();
            final service = _Service(_Bluetooth(), storage, devices, [], repo, []);
            addTearDown(service.dispose);
            await service.connectToScooterId('A');
            old.emitDisconnected();
            await Future<void>.delayed(Duration.zero);
            devices[pendingId] = pending;
            final connecting = service.connectToScooterId(pendingId, automatic: automatic);
            final settled = succeeds ? connecting : expectLater(connecting, throwsStateError);
            await Future<void>.delayed(Duration.zero);
            expect(pending.timeouts.length, 1);
            final beforeDevice = service.myScooter;
            final beforeConnected = service.connected;
            final beforeState = service.state;
            final beforeUpdates = List.of(service.updates);
            final beforeDisconnects = [old.disconnects, pending.disconnects];
            var notifications = 0;
            void changed() => notifications++;
            service.addListener(changed);
            final forgottenId = entry == 'saved-B' ? 'B' : 'A';
            if (entry == 'shared') {
              await service.actions.forgetCurrentScooter();
            } else {
              await service.forgetSavedScooter(forgottenId);
            }
            expect([old.disconnects, pending.disconnects], beforeDisconnects);
            expect(old.bondRemovals, 0);
            expect(pending.bondRemovals, 0);
            expect(devices.values.every((device) => device.bondRemovals == 0), true);
            expect(storage.removals, isEmpty);
            expect(service.myScooter, same(beforeDevice));
            expect(service.connected, beforeConnected);
            expect(service.state, beforeState);
            expect(service.updates, beforeUpdates);
            expect(notifications, 0);
            expect((repo.commandCharacteristic as _Characteristic).writes, isEmpty);
            service.removeListener(changed);
            if (succeeds) {
              pending.connection.complete();
            } else {
              pending.connection.completeError(StateError('controlled pending failure'));
            }
            await settled;
            final phoneDevice =
                service.myScooter?.remoteId.str == forgottenId ? service.myScooter! as _Device : devices[forgottenId]!;
            await service.forgetSavedScooter(forgottenId);
            expect(phoneDevice.bondRemovals, 1);
            expect(storage.removals, [forgottenId]);
            expect(storage.scooters.containsKey(forgottenId), false);
          });
        }
      }
    }
  }
  for (final shared in [false, true]) {
    test('${shared ? 'shared' : 'facade'} forget defers during connected ready publication until attempt finally exits',
        () async {
      final device = _Device('A')..connection.complete();
      final storage = _Storage();
      final repo = _Repository()..discovery.complete();
      final service = _Service(_Bluetooth(), storage, {'A': device}, [], repo, []);
      addTearDown(service.dispose);
      Future<void>? deferred;
      service.addListener(() {
        if (service.connected && deferred == null) {
          deferred = shared ? service.actions.forgetCurrentScooter() : service.forgetSavedScooter('A');
        }
      });
      await service.connectToScooterId('A');
      expect(deferred, isNotNull);
      await deferred;
      expect(storage.removals, isEmpty);
      expect(device.disconnects, 0);
      expect(device.bondRemovals, 0);
      expect(service.connected, true);
      await service.forgetSavedScooter('A');
      expect(device.bondRemovals, 1);
      expect(storage.removals, ['A']);
    });
  }
  for (final automatic in [false, true]) {
    for (final failedId in ['A', 'B']) {
      for (final forgottenId in ['A', 'B']) {
        test('forget $forgottenId after ${automatic ? 'automatic' : 'manual'} failed $failedId attempt removes locally',
            () async {
          final a = _Device('A')..connection.complete();
          final b = _Device('B');
          final devices = {'A': a, 'B': b};
          final storage = _Storage();
          final repo = _Repository()..discovery.complete();
          final service = _Service(_Bluetooth(), storage, devices, [], repo, []);
          addTearDown(service.dispose);
          await service.connectToScooterId('A');
          if (failedId == 'A') {
            a.emitDisconnected();
            await Future<void>.delayed(Duration.zero);
            devices['A'] = _Device('A');
          }
          final failedDevice = devices[failedId]!;
          final attempt = service.connectToScooterId(failedId, automatic: automatic);
          final checked = expectLater(attempt, throwsStateError);
          await Future<void>.delayed(Duration.zero);
          failedDevice.connection.completeError(StateError('connect failed before publication'));
          await checked;
          expect(service.connected, false);
          final phoneDevice =
              service.myScooter?.remoteId.str == forgottenId ? service.myScooter! as _Device : devices[forgottenId]!;
          await service.forgetSavedScooter(forgottenId);
          expect(phoneDevice.bondRemovals, 1);
          expect(storage.removals, [forgottenId]);
          expect(storage.scooters.containsKey(forgottenId), false);
          expect(storage.scooters.containsKey(forgottenId == 'A' ? 'B' : 'A'), true);
          expect((repo.commandCharacteristic as _Characteristic).writes, isEmpty);
        });
      }
    }
  }
  for (final automatic in [false, true]) {
    for (final attemptedId in ['A', 'B']) {
      test('unbound forget rejects later ${automatic ? 'automatic' : 'manual'} failed $attemptedId attempt', () async {
        final retained = _Device('A');
        final attempted = _Device(attemptedId);
        final devices = {'A': retained, attemptedId: attempted};
        final storage = _Storage();
        final service = _Service(_Bluetooth(), storage, devices, [], _Repository(), []);
        addTearDown(service.dispose);
        service.myScooter = retained;
        retained.disconnectGate = Completer<void>();
        final forgetting = service.forgetSavedScooter('A');
        await Future<void>.delayed(Duration.zero);
        final attempt = service.connectToScooterId(attemptedId, automatic: automatic);
        final checked = expectLater(attempt, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        attempted.connection.completeError(StateError('later attempt failed'));
        await checked;
        retained.disconnectGate!.complete();
        await forgetting;
        expect(retained.bondRemovals, 0);
        expect(attempted.bondRemovals, 0);
        expect(storage.removals, isEmpty);
      });
    }
  }
  for (final binding in ['disconnected', 'unbound', 'never-connected']) {
    test('forget $binding scooter removes phone bond and saved record', () async {
      final a = _Device('A')..connection.complete();
      final storage = _Storage()..scooters.remove('B');
      final repo = _Repository()..discovery.complete();
      final service = _Service(_Bluetooth(), storage, {'A': a}, [], repo, []);
      addTearDown(service.dispose);
      if (binding == 'disconnected') {
        await service.connectToScooterId('A');
        a.emitDisconnected();
        await Future<void>.delayed(Duration.zero);
        expect(service.connected, false);
        expect(service.myScooter, same(a));
      } else if (binding == 'unbound') {
        service.myScooter = a;
      }
      await service.forgetSavedScooter('A');
      expect(a.bondRemovals, 1);
      expect(storage.removals, ['A']);
      expect(storage.scooters, isEmpty);
      expect(service.myScooter, null);
      expect(service.scooterName, null);
      expect((repo.commandCharacteristic as _Characteristic).writes, isEmpty);
    });
  }
  for (final replacement in ['B', 'same-id', 'dispose']) {
    test('disconnected forget stops after $replacement during transport cleanup', () async {
      final a = _Device('A')..connection.complete();
      final b = _Device(replacement == 'same-id' ? 'A' : 'B')..connection.complete();
      final devices = {'A': a, 'B': b};
      final storage = _Storage();
      final repo = _Repository()..discovery.complete();
      final service = _Service(_Bluetooth(), storage, devices, [], repo, []);
      await service.connectToScooterId('A');
      a.emitDisconnected();
      await Future<void>.delayed(Duration.zero);
      a.disconnectGate = Completer<void>();
      final forgetting = service.forgetSavedScooter('A');
      // Attach error handling immediately so the before-fix failure is reported.
      final checked = expectLater(forgetting, completes);
      await Future<void>.delayed(Duration.zero);
      if (replacement == 'dispose') {
        service.dispose();
      } else {
        if (replacement == 'same-id') devices['A'] = b;
        await service.connectToScooterId(b.remoteId.str);
      }
      a.disconnectGate!.complete();
      await checked;
      expect(a.bondRemovals, 0);
      expect(b.bondRemovals, 0);
      expect(storage.removals, isEmpty);
      if (replacement != 'dispose') {
        expect(service.myScooter, same(b));
        expect(service.connected, true);
        expect(b.disconnects, 0);
        service.dispose();
      }
    });
  }
  for (final phase in ['phone-bond', 'store-remove', 'cache-refetch']) {
    for (final replacement in ['same-id', 'dispose']) {
      test('forget $phase completion does not publish after $replacement', () async {
        final a = _Device('A')..connection.complete();
        final next = _Device('A')..connection.complete();
        final devices = {'A': a};
        final storage = _Storage()..scooters.remove('B');
        final repo = _Repository()..discovery.complete();
        final service = _Service(_Bluetooth(), storage, devices, [], repo, []);
        if (phase != 'phone-bond') {
          await service.connectToScooterId('A');
          a.emitDisconnected();
          await Future<void>.delayed(Duration.zero);
        }
        final gate = Completer<void>();
        if (phase == 'phone-bond') a.bondGate = gate;
        if (phase == 'store-remove') storage.removeGate = gate;
        if (phase == 'cache-refetch') storage.loadGate = gate;
        final forgetting = service.forgetSavedScooter('A');
        await Future<void>.delayed(Duration.zero);
        if (replacement == 'dispose') {
          service.dispose();
        } else {
          devices['A'] = next;
          await service.connectToScooterId('A');
          service.scooterName = 'Replacement';
        }
        final updates = service.updates.length;
        gate.complete();
        await forgetting;
        expect(service.updates.length, updates);
        expect(next.bondRemovals, 0);
        if (replacement != 'dispose') {
          expect(service.connected, true);
          expect(service.myScooter, same(next));
          expect(service.scooterName, 'Replacement');
          service.dispose();
        }
      });
    }
  }
  test('delayed hazard never writes replacement or after its timeout', () {
    fakeAsync((time) {
      final a = _Device('A')..linked = true;
      final b = _Device('B')..linked = true;
      final ra = _Repository()..discovery.complete();
      a.connection.complete();
      b.connection.complete();
      final service = _Service(_Bluetooth(), _Storage(), {'A': a, 'B': b}, [], ra, []);
      service.connectToScooterId('A');
      time.flushMicrotasks();
      service.hazard().timeout(const Duration(milliseconds: 100)).catchError((Object _) {});
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 100));
      service.connectToScooterId('B');
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect((ra.commandCharacteristic as _Characteristic).writes, ['scooter:blinker both']);
      service.dispose();
    });
  });
  test('service isolate cooldown does not call UI background facade', () {
    fakeAsync((time) {
      final previous = FlutterBackgroundServicePlatform.instance;
      final background = RecordingBackgroundService();
      FlutterBackgroundServicePlatform.instance = background;
      final service = _Service(_Bluetooth(), _Storage(), {}, [], _Repository(), [])..isInBackgroundService = true;
      service.autoUnlockCooldown();
      expect(background.updates, isEmpty);
      expect(service.autoUnlockCoolingDown, true);
      time.elapse(const Duration(seconds: 59));
      expect(service.autoUnlockCoolingDown, true);
      time.elapse(const Duration(seconds: 1));
      expect(service.autoUnlockCoolingDown, false);
      service.dispose();
      FlutterBackgroundServicePlatform.instance = previous;
    });
  });
  test('facade delivers a typed handlebar warning without failing acknowledged unlock', () {
    fakeAsync((time) {
      StatisticsHelper().prefs = _NoLogsPreferences();
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
        return null;
      });
      final device = _Device('A')..connection.complete();
      final repository = _Repository()..discovery.complete();
      final service = _Service(_Bluetooth(), _Storage(), {'A': device}, [], repository, []);
      service.connectToScooterId('A');
      time.flushMicrotasks();
      service.vehicle.handlebarsLocked = true;
      final warnings = <String>[];
      final subscription = service.actionWarnings.listen((warning) {
        warnings.add('${warning.action.scooterId}:${warning.action.kind.name}:${warning.didNotUnlock}');
      });
      var done = false;
      service.unlock(source: EventSource.background).then((_) => done = true);
      time.flushMicrotasks();
      expect((repository.commandCharacteristic as _Characteristic).writes, ['scooter:state unlock']);
      expect(haptics, ['HapticFeedbackType.heavyImpact']);
      expect(warnings, isEmpty);
      time.elapse(const Duration(seconds: 5));
      expect(done, true);
      expect(warnings, ['A:unlock:true']);
      subscription.cancel();
      service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });
  test('UI cooldown relays once and disposal cancels local expiry', () {
    fakeAsync((time) {
      final background = RecordingBackgroundService();
      FlutterBackgroundServicePlatform.instance = background;
      final service = _Service(_Bluetooth(), _Storage(), {}, [], _Repository(), []);
      service.autoUnlockCooldown();
      expect(service.autoUnlockCoolingDown, true);
      expect(background.updates, [
        {'method': 'autoUnlockCooldown', 'args': null}
      ]);
      service.dispose();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });
}

class _NoLogsPreferences extends SharedPreferencesAsync {
  @override
  Future<bool?> getBool(String key) async => false;
}
