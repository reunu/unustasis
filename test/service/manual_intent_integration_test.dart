import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart' show ScooterState;
import 'dart:convert';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:unustasis/background/notification_handler.dart';
import 'package:flutter/material.dart';
import 'package:unustasis/background/bg_service.dart' as background;
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

  void Function()? onMostRecent;
  @override
  SavedScooter? getMostRecent() {
    onMostRecent?.call();
    return scooters.values.firstOrNull;
  }

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
  @override
  bool get isScanningNow => platformScanning;
  bool platformScanning = false;
  late final scanEvents = StreamController<bool>.broadcast();
  int stops = 0;
  int scanStreamReads = 0;

  @override
  Stream<bool> get isScanning {
    scanStreamReads++;
    return scanEvents.stream;
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
  bool silentFailure = false;
  int rssiReads = 0;
  int rssiValue = -70;
  Completer<int>? rssiGate;
  @override
  Future<int> readRssi({int timeout = 15}) async {
    rssiReads++;
    if (rssiGate != null) return rssiGate!.future;
    if (silentFailure) throw StateError('Silent disconnect');
    return rssiValue;
  }

  @override
  bool get isDisconnected => forceDisconnected || !linked;
  bool forceDisconnected = false;

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
  bool failWrite = false;
  Completer<void>? writeGate;
  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    writes.add(String.fromCharCodes(value));
    await writeGate?.future;
    if (failWrite) throw StateError("Uncertain write acknowledgement");
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
  _Repository({String state = 'parked'}) : super(_Device('repository-only')) {
    commandCharacteristic = characteristic([]);
    hibernationCommandCharacteristic = null;
    stateCharacteristic = characteristic(state.codeUnits);
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
  // ignore: use_super_parameters
  _Service(super.flutterBluePlus, _Storage storage, Map<String, _Device> devices, List<String> deviceRequests,
      _Repository repository, List<BluetoothDevice> repositories,
      {Future<LatLng?> Function()? pollLocation, bool initializeRuntime = false, bool background = true,
      bool allowAutomaticActions = true})
      : super(
          pollLocation: pollLocation ?? (() async => null),
          storage: storage,
          initializeRuntime: initializeRuntime,
          isInBackgroundService: background,
          allowAutomaticActions: allowAutomaticActions,
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

class _EventPreferences extends Fake implements SharedPreferencesAsync {
  @override
  Future<bool?> getBool(String key) async => true;
  final events = <String>[];
  @override
  Future<List<String>?> getStringList(String key) async => events.toList();
  @override
  Future<void> setStringList(String key, List<String> value) async {
    events.clear();
    events.addAll(value);
  }
}

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();
  Completer<void>? nameWriteGate;
  bool failWrite = false;
  bool throwsError = true;
  void Function()? onRemove;
  final trace = <String>[];
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    trace.add(key.replaceFirst('flutter.', ''));
    if (failWrite) {
      if (throwsError) throw StateError('Persistence failed');
      return false;
    }
    if (key == 'flutter.pendingWidgetActionName') await nameWriteGate?.future;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    final result = await super.remove(key);
    final callback = onRemove;
    onRemove = null;
    callback?.call();
    return result;
  }
}

// Faults affect the real legacy preferences adapter, including its optimistic cache.
class _ClaimPreferences extends InMemorySharedPreferencesStore {
  _ClaimPreferences() : super.empty();
  int reloads = 0;
  final failures = <String, bool>{}; // true throws; false returns false (writes only).
  final afterPersistence = <String>{};
  final calls = <String>[];
  Future<void> Function(String)? after;

  Future<bool> _write(String operation, Future<bool> Function() write) async {
    calls.add(operation);
    final failure = failures.remove(operation);
    if (failure == null || afterPersistence.contains(operation)) await write();
    await after?.call(operation);
    if (failure == true) throw StateError('Injected $operation failure');
    return failure == null;
  }
  @override
  Future<bool> setValue(String valueType, String key, Object value) => _write(
    key == 'flutter.pendingWidgetAction' ? (value == false ? 'claim' : 'restoreFlag') : 'restoreName',
    () => super.setValue(valueType, key, value));
  @override
  Future<bool> remove(String key) => _write('remove', () => super.remove(key));
  @override
  Future<Map<String, Object>> getAll() async {
    final operation = 'reload${++reloads}';
    calls.add(operation);
    if (failures.remove(operation) != null) throw StateError('Injected $operation failure');
    final result = await super.getAll();
    await after?.call(operation);
    return result;
  }
  Future<void> replaceWith(String name, {bool armed = true}) async {
    await super.setValue('String', 'flutter.pendingWidgetActionName', name);
    await super.setValue('Bool', 'flutter.pendingWidgetAction', armed);
  }
  void arm() { reloads = 0; calls.clear(); }
}

class _WidgetHarness {
  _WidgetHarness({bool holdA = false}) {
    if (!holdA) a.connection.complete();
    b.connection.complete();
    service = ScooterService(bluetooth,
        isInBackgroundService: true,
        initializeRuntime: false,
        storage: _Storage(),
        pollLocation: () async => null,
        deviceFromId: (id) {
          requests.add(id);
          return id == 'A' ? a : b;
        },
        repositoryFactory: (device) => device.remoteId.toString() == 'A' ? repoA : repoB);
    background.scooterService = service;
  }
  final a = _Device('A');
  final b = _Device('B');
  final bluetooth = _Bluetooth();
  final requests = <String>[];
  final repoA = _Repository()..discovery.complete();
  final repoB = _Repository()..discovery.complete();
  late final ScooterService service;
  List<String> writes(String id) => ((id == 'A' ? repoA : repoB).commandCharacteristic as _Characteristic).writes;
  Future<void> pending(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pendingWidgetAction', true);
    await prefs.setString('pendingWidgetActionName', name);
  }

  Future<void> expectPending(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getBool('pendingWidgetAction'), name != null);
    expect(prefs.getString('pendingWidgetActionName'), name);
  }

  void dispose() => service.dispose();
}

final class _RuntimePreferences extends SharedPreferencesAsyncPlatform {
  final reads = <String>[];
  final values = <String, Object>{};
  final gates = <String, Completer<void>>{};
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    reads.add(key); await gates[key]?.future; return values[key] as String?;
  }
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    reads.add(key); await gates[key]?.future; return values[key] as bool?;
  }
  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async {
    reads.add(key); await gates[key]?.future; return values[key] as int?;
  }
  @override
  Future<void> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) async {
    reads.add('remove'); await gates['remove']?.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected $invocation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
    SharedPreferences.setMockInitialValues({});
    StatisticsHelper().locationPermission = false;
    StatisticsHelper().prefs = _EventPreferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (_) async => true);
  });

  testWidgets('onboarding manual connect then disconnect and Home start retries pinned A', (tester) async {
    final a = _Device('A')..connection.complete();
    final b = _Device('B')..connection.complete();
    final repo = _Repository()..discovery.complete();
    final requests = <String>[];
    final service = _Service(_Bluetooth(), _Storage(), {'A': a, 'B': b}, requests, repo, []);
    await service.connectToScooterId('A'); // Actual onboarding entry point.
    expect(service.connected, isTrue);
    a.emitDisconnected();
    await tester.pump();
    service.start(); // Actual Home reconnect entry point.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    // Drain real subscription-cancellation completions outside virtual timers.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final count = a.timeouts.length;
    if (a.connections.length > 1) a.connections[1].complete();
    await tester.pump();
    service.dispose();
    await tester.pump();
    expect(count, 2, reason: 'Retained manual target must retry, not no-op');
    expect(requests, everyElement('A'));
  });

  testWidgets('silent suspension disconnect then resume retries pinned A', (tester) async {
    final a = _Device('A')..connection.complete();
    final repo = _Repository()..discovery.complete();
    final service = _Service(_Bluetooth(), _Storage(), {'A': a}, [], repo, []);
    await service.connectToScooterId('A');
    a.silentFailure = true;
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    // Drain real subscription-cancellation completions outside virtual timers.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    final count = a.timeouts.length;
    if (a.connections.length > 1) a.connections[1].complete();
    await tester.pump();
    service.dispose();
    await tester.pump();
    expect(count, 2, reason: 'RSSI-detected dead manual link must retry');
  });

  test('explicit widget unlock under manual gate connects pinned A and issues once', () {
    fakeAsync((time) {
      final a = _Device('A')..connection.complete();
      final repo = _Repository()..discovery.complete();
      final service = _Service(_Bluetooth(), _Storage(), {'A': a}, [], repo, []);
      background.scooterService = service;
      background.handleForegroundConnectionUpdate(service, {'manualConnectionTarget': 'A'});
      SharedPreferences.setMockInitialValues({'pendingWidgetAction': true, 'pendingWidgetActionName': 'unlock'});
      background.executeWidgetAction('unlock');
      time.flushMicrotasks();
      final writes = (repo.commandCharacteristic as _Characteristic).writes.toList();
      service.dispose();
      time.elapse(const Duration(seconds: 3));
      expect(writes, ['scooter:state unlock']);
    });
  });
  test('widget connect links the saved scooter without issuing a vehicle command', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    await h.pending('connect');
    await background.executeWidgetAction('connect');
    expect(h.requests, ['A']);
    expect(h.writes('A'), isEmpty);
    expect(h.writes('B'), isEmpty);
    expect(h.service.connected, isTrue);
    await h.expectPending(null);
  });

  test('widget connect on an existing connection consumes request without reconnect or actuation', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    await h.service.connectToScooterId('A');
    h.requests.clear();
    await h.pending('connect');
    await background.executeWidgetAction('connect');
    expect(h.requests, isEmpty);
    expect(h.writes('A'), isEmpty);
    expect(h.writes('B'), isEmpty);
    await h.expectPending(null);
  });

  testWidgets('temporary widget reconnect uses production polling without automatic vehicle writes', (tester) async {
    final preferences = _RuntimePreferences()
      ..values['autoUnlock'] = true
      ..values['biometrics'] = false;
    SharedPreferencesAsyncPlatform.instance = preferences;
    final a = _Device('A')..connection.complete()..rssiValue = -50;
    final repo = _Repository(state: 'stand-by')..discovery.complete();
    final service = _Service(_Bluetooth(), _Storage(), {'A': a}, [], repo, [],
        initializeRuntime: true, allowAutomaticActions: false);
    background.scooterService = service;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pendingWidgetActionName', 'connect');
    await prefs.setBool('pendingWidgetAction', true);
    await background.executeWidgetAction('connect');
    expect(service.connected, isTrue);
    expect(service.state, ScooterState.standby);
    expect(service.autoUnlock, isTrue);
    expect(service.optionalAuth, isTrue);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await service.actions.pollRssi();
    expect(a.rssiReads, 0, reason: 'passive runtime does not start a proximity action');
    expect(repo.characteristics.expand((c) => c.writes), isEmpty);
    expect(preferences.values['autoUnlock'], isTrue);
    expect(prefs.getBool('pendingWidgetAction'), isFalse);

    // Explicit widget commands remain usable in the same temporary service.
    for (final action in ['unlock', 'lock', 'openseat']) {
      await prefs.setString('pendingWidgetActionName', action);
      await prefs.setBool('pendingWidgetAction', true);
      await background.executeWidgetAction(action);
    }
    expect((repo.commandCharacteristic as _Characteristic).writes,
        ['scooter:state unlock', 'scooter:state lock', 'scooter:seatbox open']);
    service.dispose();
    await tester.pump(const Duration(seconds: 6));
  });

  for (final backgroundMode in [false, true]) {
    testWidgets('production ${backgroundMode ? 'persistent background' : 'foreground'} retains opted-in keyless polling', (tester) async {
      final preferences = _RuntimePreferences()
        ..values['autoUnlock'] = true
        ..values['biometrics'] = false;
      SharedPreferencesAsyncPlatform.instance = preferences;
      final a = _Device('A')..connection.complete()..rssiValue = -50;
      final repo = _Repository(state: 'stand-by')..discovery.complete();
      final service = _Service(_Bluetooth(), _Storage(), {'A': a}, [], repo, [],
          initializeRuntime: true, background: backgroundMode);
      await service.runtimeReady;
      await service.connectToScooterId('A');
      await tester.pump(const Duration(seconds: 3));
      expect(a.rssiReads, greaterThan(0));
      expect((repo.commandCharacteristic as _Characteristic).writes, ['scooter:state unlock']);
      expect(preferences.values['autoUnlock'], isTrue);
      service.dispose();
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('enabling background scan restores automatic policy without rewriting preference', (tester) async {
    final preferences = _RuntimePreferences()
      ..values['autoUnlock'] = true
      ..values['biometrics'] = false;
    SharedPreferencesAsyncPlatform.instance = preferences;
    final a = _Device('A')..connection.complete()..rssiValue = -50;
    final repo = _Repository(state: 'stand-by')..discovery.complete();
    final service = _Service(_Bluetooth(), _Storage(), {'A': a}, [], repo, [],
        initializeRuntime: true, allowAutomaticActions: false);
    await service.runtimeReady;
    await service.connectToScooterId('A');
    await tester.pump(const Duration(seconds: 4));
    expect(repo.characteristics.expand((c) => c.writes), isEmpty);
    // _enableScanning applies this runtime-only policy before restarting RSSI.
    service.setAutomaticActionsAllowed(true);
    service.rssiTimer.start();
    await tester.pump(const Duration(seconds: 3));
    expect(a.rssiReads, greaterThan(0));
    expect((repo.commandCharacteristic as _Characteristic).writes, ['scooter:state unlock']);
    expect(service.autoUnlock, isTrue);
    expect(preferences.values['autoUnlock'], isTrue);
    service.dispose();
    await tester.pump(const Duration(seconds: 6));
  });

  for (final replacement in [null, 'lock', 'cancel']) {
    testWidgets('widget reconnect waits for storage and revalidates ${replacement ?? 'unchanged'} request', (tester) async {
      SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
      final storage = _Storage()..scooters = {}..loadGate = Completer<void>();
      final a = _Device('A')..connection.complete();
      final repo = _Repository()..discovery.complete();
      final requests = <String>[];
      final service = _Service(_Bluetooth(), storage, {'A': a}, requests, repo, [],
          initializeRuntime: true, allowAutomaticActions: false);
      background.scooterService = service;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingWidgetActionName', 'connect');
      await prefs.setBool('pendingWidgetAction', true);
      var completed = false;
      final action = background.executeWidgetAction('connect').then((_) => completed = true);
      await tester.pump(const Duration(seconds: 5));
      expect(completed, isFalse);
      expect(requests, isEmpty);
      expect(prefs.getBool('pendingWidgetAction'), isTrue);
      expect(prefs.getString('pendingWidgetActionName'), 'connect');
      if (replacement == 'cancel') {
        await prefs.setBool('pendingWidgetAction', false);
        await prefs.remove('pendingWidgetActionName');
      } else if (replacement != null) {
        await prefs.setString('pendingWidgetActionName', replacement);
      }
      storage.scooters = {'A': SavedScooter(id: 'A', name: 'Alpha', color: 1)};
      storage.loadGate!.complete();
      await tester.pump();
      await action;
      await prefs.reload();
      expect(requests, replacement == null ? ['A'] : isEmpty);
      expect(service.connected, replacement == null);
      expect(prefs.getBool('pendingWidgetAction'), replacement == 'lock');
      expect(prefs.getString('pendingWidgetActionName'), replacement == 'lock' ? 'lock' : null);
      expect(repo.characteristics.expand((c) => c.writes), isEmpty);
      service.dispose();
      await tester.pump(const Duration(seconds: 6));
    });
  }

  for (final action in ['lock', 'unlock']) {
    test('explicit $action under foreground gate bypasses passive suppression only for pinned A', () async {
      final h = _WidgetHarness();
      addTearDown(h.dispose);
      h.service.setManualConnectionTarget('A');
      expect(await h.service.attemptLatestAutoConnection(), isFalse);
      expect(h.requests, isEmpty);
      await h.pending(action);
      await background.executeWidgetAction(action);
      expect(h.writes('A'), ['scooter:state $action']);
      expect(h.writes('B'), isEmpty);
      expect(h.requests, ['A']);
      expect(h.bluetooth.stops, 0, reason: 'Explicit route must not scan');
      await h.expectPending(null);
      await background.executeWidgetAction(action); // Late duplicate fast path.
      expect(h.writes('A'), hasLength(1));
      expect(await h.service.attemptLatestAutoConnection(), isFalse);
    });
  }

  test('already connected background B cannot receive widget action pinned to foreground A', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    await h.service.connectToScooterId('B', automatic: true);
    h.service.setManualConnectionTarget('A');
    await h.pending('lock');
    await background.executeWidgetAction('lock');
    expect(h.service.myScooter?.remoteId.toString(), 'A');
    expect(h.writes('A'), ['scooter:state lock']);
    expect(h.writes('B'), isEmpty);
    expect(h.b.disconnects, 1);
  });

  test('local manual pin outranks a different most-recent saved scooter', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    await h.service.connectToScooterId('B');
    h.b.emitDisconnected();
    await Future<void>.delayed(Duration.zero);
    h.b.connections.add(Completer<void>()..complete());
    await h.pending('unlock');
    await background.executeWidgetAction('unlock');
    expect(h.writes('B'), ['scooter:state unlock']);
    expect(h.writes('A'), isEmpty);
    expect(h.requests, ['B', 'B']);
  });

  test('pin change during connect retains request and does not actuate either scooter', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    await h.pending('unlock');
    final action = background.executeWidgetAction('unlock');
    await Future<void>.delayed(Duration.zero);
    expect(h.a.timeouts, hasLength(1));
    h.service.setManualConnectionTarget('B');
    h.a.connection.complete();
    await action;
    expect(h.writes('A'), isEmpty);
    expect(h.writes('B'), isEmpty);
    await h.expectPending('unlock');
    await background.executeWidgetAction('unlock');
    expect(h.writes('B'), ['scooter:state unlock']);
  });

  test('connection failure before issuance retains matching widget request', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    await h.pending('lock');
    final action = background.executeWidgetAction('lock');
    await Future<void>.delayed(Duration.zero);
    h.a.connection.completeError(StateError('Connection refused'));
    await action;
    expect(h.writes('A'), isEmpty);
    await h.expectPending('lock');
  });

  test('pending session attempt defers widget request without superseding it', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    final connection = h.service.connectToScooterId('A', automatic: true);
    await Future<void>.delayed(Duration.zero);
    await h.pending('lock');
    await background.executeWidgetAction('lock');
    expect(h.requests, ['A']);
    expect(h.a.disconnects, 0);
    expect(h.writes('A'), isEmpty);
    await h.expectPending('lock');
    h.a.connection.complete();
    await connection;
    await background.executeWidgetAction('lock');
    expect(h.writes('A'), ['scooter:state lock']);
    await h.expectPending(null);
  });

  test('new different request arriving during connect is not cleared or issued by old invoke', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    await h.pending('unlock');
    final action = background.executeWidgetAction('unlock');
    await Future<void>.delayed(Duration.zero);
    await h.pending('lock');
    h.a.connection.complete();
    await action;
    expect(h.writes('A'), isEmpty);
    await h.expectPending('lock');
    await background.executeWidgetAction('unlock');
    await h.expectPending('lock');
    await background.executeWidgetAction('lock');
    expect(h.writes('A'), ['scooter:state lock']);
  });

  test('pin change while claiming restores unissued request without actuating stale target', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    final prefs = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = prefs;
    await h.pending('unlock');
    prefs.onRemove = () => h.service.setManualConnectionTarget('B');
    await background.executeWidgetAction('unlock');
    expect(h.writes('A'), isEmpty);
    expect(h.writes('B'), isEmpty);
    await h.expectPending('unlock');
  });

  test('uncertain post-issue write failure consumes request and cannot replay automatically', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    (h.repoA.commandCharacteristic as _Characteristic).failWrite = true;
    await h.pending('unlock');
    await background.executeWidgetAction('unlock');
    expect(h.writes('A'), ['scooter:state unlock']);
    await h.expectPending(null);
    await background.executeWidgetAction('unlock');
    expect(h.writes('A'), hasLength(1));
  });

  test('seat dispatch is awaited and concurrent invokes cannot issue it twice', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    final command = h.repoA.commandCharacteristic as _Characteristic;
    command.writeGate = Completer<void>();
    await h.pending('openseat');
    var finished = false;
    final action = background.executeWidgetAction('openseat').then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(command.writes, ['scooter:seatbox open']);
    await background.executeWidgetAction('openseat');
    command.writeGate!.complete();
    await action;
    expect(command.writes, hasLength(1));
  });

  for (final action in ['lock', 'unlock', 'openseat']) {
    test('notification $action persists before invoke and consumer handles it once', () async {
      final h = _WidgetHarness();
      addTearDown(h.dispose);
      h.service.setManualConnectionTarget('A');
      final prefs = _ControlledPreferences()..nameWriteGate = Completer<void>();
      SharedPreferencesStorePlatform.instance = prefs;
      final messages = RecordingBackgroundService();
      FlutterBackgroundServicePlatform.instance = messages;
      final producer = notificationTapBackground(NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction, actionId: action));
      await Future<void>.delayed(Duration.zero);
      expect(messages.updates, isEmpty);
      expect(prefs.trace, ['pendingWidgetActionName']);
      prefs.nameWriteGate!.complete();
      await producer;
      expect(prefs.trace, ['pendingWidgetActionName', 'pendingWidgetAction']);
      await h.expectPending(action);
      expect(messages.updates.single['method'], action);
      await background.executeWidgetAction(action);
      await h.expectPending(null);
      await background.executeWidgetAction(action);
      expect(h.writes('A'), hasLength(1));
    });
  }

  for (final throwsError in [true, false]) {
    test('notification persistence failure (throws=$throwsError) must not invoke', () async {
      final prefs = _ControlledPreferences()
        ..failWrite = true
        ..throwsError = throwsError;
      SharedPreferencesStorePlatform.instance = prefs;
      final messages = RecordingBackgroundService();
      FlutterBackgroundServicePlatform.instance = messages;
      await notificationTapBackground(const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction, actionId: 'unlock'));
      expect(messages.updates, isEmpty);
    });
  }

  testWidgets('repeated reconnect entry calls share one retry and do not release manual intent', (tester) async {
    final a = _Device('A')..connection.complete();
    final repo = _Repository()..discovery.complete();
    final bluetooth = _Bluetooth();
    final service = _Service(bluetooth, _Storage(), {'A': a}, [], repo, []);
    await service.connectToScooterId('A');
    a.emitDisconnected();
    await tester.pump();
    service.start();
    service.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    // Drain real subscription-cancellation completions outside virtual timers.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(a.timeouts, hasLength(2));
    service.start(); // A connection is pending; no competing attempt/listener.
    await tester.pump();
    expect(a.timeouts, hasLength(2));
    expect(bluetooth.scanStreamReads, 1);
    expect(service.updates.where((e) => e['manualConnectionTarget'] == ''), isEmpty);
    a.connections[1].complete();
    await tester.pump();
    service.start(); // A usable connection is retained.
    await tester.pump();
    expect(a.timeouts, hasLength(2));
    service.dispose();
    await tester.pump();
  });

  testWidgets('new manual B supersedes scheduled reconnect of A without generic scan', (tester) async {
    final a = _Device('A')..connection.complete();
    final b = _Device('B')..connection.complete();
    final repo = _Repository()..discovery.complete();
    final requests = <String>[];
    final service = _Service(_Bluetooth(), _Storage(), {'A': a, 'B': b}, requests, repo, []);
    await service.connectToScooterId('A');
    a.emitDisconnected();
    await tester.pump();
    service.start();
    await tester.pump();
    final connectingB = service.connectToScooterId('B');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await connectingB;
    await tester.pump(const Duration(seconds: 3));
    expect(requests, ['A', 'B']);
    expect(service.myScooter?.remoteId.toString(), 'B');
    service.dispose();
    await tester.pump();
  });

  testWidgets('restart false makes one targeted attempt and does not arm retries', (tester) async {
    final a = _Device('A')..connection.complete();
    final repo = _Repository()..discovery.complete();
    final bluetooth = _Bluetooth();
    final service = _Service(bluetooth, _Storage(), {'A': a}, [], repo, []);
    await service.connectToScooterId('A');
    a.emitDisconnected();
    await tester.pump();
    service.start(restart: false);
    // Drain real subscription-cancellation completions outside virtual timers.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(a.timeouts, hasLength(2));
    a.connections[1].completeError(StateError('No link'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(a.timeouts, hasLength(2));
    expect(bluetooth.scanStreamReads, 0);
    service.dispose();
    await tester.pump();
  });

  test('new same-ID attempt during explicit connect prevents old request continuation', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.setManualConnectionTarget('A');
    await h.pending('unlock');
    final action = background.executeWidgetAction('unlock');
    await Future<void>.delayed(Duration.zero);
    final replacement = h.service.connectToScooterId('A', automatic: true);
    await Future<void>.delayed(Duration.zero);
    expect(h.a.timeouts, hasLength(2));
    h.a.connections[1].complete();
    await replacement;
    h.a.connection.complete();
    await action;
    expect(h.writes('A'), isEmpty);
    await h.expectPending('unlock');
    await background.executeWidgetAction('unlock');
    expect(h.writes('A'), ['scooter:state unlock']);
  });

  test('disposal during explicit connection preserves the unissued pending request', () async {
    final h = _WidgetHarness(holdA: true);
    h.service.setManualConnectionTarget('A');
    await h.pending('unlock');
    final action = background.executeWidgetAction('unlock');
    await Future<void>.delayed(Duration.zero);
    h.dispose();
    h.a.connection.complete();
    await action;
    expect(h.writes('A'), isEmpty);
    await h.expectPending('unlock');
  });

  test('no usable target retains pending request rather than issuing against cached identity', () async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    h.service.savedScooters.clear();
    await h.pending('unlock');
    await background.executeWidgetAction('unlock');
    expect(h.requests, isEmpty);
    expect(h.writes('A'), isEmpty);
    await h.expectPending('unlock');
  });
  testWidgets('runtime initialization delayed cache cannot publish after disposal', (tester) async {
    SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
    final storage = _Storage()..loadGate = Completer<void>();
    final bluetooth = _Bluetooth();
    final service = _Service(bluetooth, storage, {}, [], _Repository(), [], initializeRuntime: true);
    var notifications = 0;
    service.addListener(() => notifications++);
    service.dispose();
    storage.loadGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(notifications, 0);
    await tester.pump(const Duration(seconds: 65));
  });

  testWidgets('runtime normal init is idempotent and disposal stops scans location RSSI and heartbeat', (tester) async {
    final prefs = _RuntimePreferences()..values['biometrics'] = true..values['autoUnlock'] = true;
    SharedPreferencesAsyncPlatform.instance = prefs;
    final storage = _Storage();
    final bluetooth = _Bluetooth();
    final a = _Device('A')..connection.complete();
    final repo = _Repository()..discovery.complete();
    var locations = 0;
    final service = _Service(bluetooth, storage, {'A': a}, [], repo, [],
        initializeRuntime: true, background: false,
        pollLocation: () async { locations++; return const LatLng(1, 2); });
    await tester.pump();
    await service.runtimeReady;
    await service.runtimeReady;
    expect(storage.loads, 1);
    expect(bluetooth.scanStreamReads, 1);
    expect(service.scooterName, 'Alpha');
    expect(prefs.reads, ['pendingNavigation', 'autoUnlock', 'autoUnlockThreshold',
      'biometrics', 'openSeatOnUnlock', 'hazardLocking', 'unlockedHandlebarsWarning']);
    await service.connectToScooterId('A');
    await tester.pump();
    expect(locations, 1);
    service.updates.clear();
    bluetooth.scanEvents.add(true);
    await tester.pump();
    expect(service.scanning, isTrue);
    await tester.pump(const Duration(seconds: 60));
    expect(locations, 4);
    expect(a.rssiReads, greaterThan(0));
    expect(service.updates.where((e) => e['manualConnectionTarget'] == 'A'), hasLength(1));
    expect(storage.scooters['A']!.lastLocation, const LatLng(1, 2));
    service.dispose();
    await tester.pump();
    final reads = a.rssiReads;
    final updates = service.updates.length;
    bluetooth.scanEvents.add(false);
    await tester.pump(const Duration(seconds: 65));
    expect(bluetooth.scanEvents.hasListener, isFalse);
    expect(locations, 4); expect(a.rssiReads, reads); expect(service.updates.length, updates);
    expect(tester.takeException(), isNull);
  });

  for (final phase in ['selection', 'pendingNavigation', 'remove', 'autoUnlock',
    'autoUnlockThreshold', 'biometrics', 'openSeatOnUnlock', 'hazardLocking', 'unlockedHandlebarsWarning']) {
    testWidgets('runtime disposal during $phase has no later publication or live polling', (tester) async {
      final prefs = _RuntimePreferences();
      SharedPreferencesAsyncPlatform.instance = prefs;
      final storage = _Storage();
      final gate = Completer<void>();
      if (phase == 'remove') prefs.values['pendingNavigation'] = 'invalid JSON';
      if (phase != 'selection') prefs.gates[phase] = gate;
      final bluetooth = _Bluetooth();
      late _Service service;
      if (phase == 'selection') storage.onMostRecent = () => service.dispose();
      service = _Service(bluetooth, storage, {}, [], _Repository(), [], initializeRuntime: true);
      var notifications = 0;
      service.addListener(() => notifications++);
      await tester.pump();
      if (phase != 'selection') {
        expect(prefs.reads, contains(phase));
        service.dispose();
      }
      final before = notifications;
      if (phase != 'selection') gate.complete();
      await tester.pump();
      await service.runtimeReady;
      await tester.pump(const Duration(seconds: 65));
      expect(notifications, before);
      expect(bluetooth.scanEvents.hasListener, isFalse);
      expect(tester.takeException(), isNull);
      if (phase == 'selection' || phase == 'pendingNavigation' || phase == 'remove') {
        expect(prefs.reads, isNot(contains('autoUnlock')));
      }
    });
  }

  for (final target in ['A', 'B']) {
  testWidgets('manual $target during startup cannot be overwritten by A cache but global restoration completes', (tester) async {
    final prefs = _RuntimePreferences()
      ..values['openSeatOnUnlock'] = true
      ..values['pendingNavigation'] = jsonEncode({'latitude': 1.0, 'longitude': 2.0, 'name': 'Home', 'id': 'x'});
    SharedPreferencesAsyncPlatform.instance = prefs;
    final storage = _Storage()..loadGate = Completer<void>();
    final b = _Device(target)..connection.complete();
    final repo = _Repository()..discovery.complete();
    final service = _Service(_Bluetooth(), storage, {target: b}, [], repo, [], initializeRuntime: true);
    await service.connectToScooterId(target);
    storage.loadGate!.complete();
    await tester.pump();
    await service.runtimeReady;
    expect(service.scooterName, target == 'A' ? 'Alpha' : 'Beta');
    expect(service.primarySOC, 90);
    expect(service.settings.openSeatOnUnlock, isTrue);
    expect(prefs.reads, contains('pendingNavigation'));
    expect(service.pendingNavigation?.id, 'x');
    service.dispose(); await tester.pump();
  });
  }

  for (final replacement in [false, true]) {
    testWidgets('delayed disconnected refetch is suppressed on ${replacement ? 'new target' : 'disposal'}', (tester) async {
      SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
      final storage = _Storage();
      final b = _Device('B')..connection.complete();
      final service = _Service(_Bluetooth(), storage, {'B': b}, [], _Repository()..discovery.complete(), [],
          initializeRuntime: true);
      await tester.pump(); await service.runtimeReady;
      storage.loadGate = Completer<void>();
      final refetch = service.refetchSavedScooters();
      if (replacement) { await service.connectToScooterId('B'); } else { service.dispose(); }
      storage.loadGate!.complete(); await tester.pump(); await refetch;
      if (replacement) { expect(service.scooterName, 'Beta'); service.dispose(); }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('runtime scan resync waits for real background and retains live manual link', (tester) async {
    SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
    final bluetooth = _Bluetooth();
    final a = _Device('A')..connection.complete();
    final service = _Service(bluetooth, _Storage(), {'A': a}, [], _Repository()..discovery.complete(), [],
        initializeRuntime: true);
    await tester.pump(); await service.runtimeReady;
    await service.connectToScooterId('A');
    service.scanning = true;
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.scanning, isTrue); expect(a.rssiReads, 0);
    service.didChangeAppLifecycleState(AppLifecycleState.hidden);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.scanning, isFalse); expect(a.rssiReads, 1);
    expect(a.timeouts, hasLength(1));
    service.dispose(); await tester.pump();
  });

  testWidgets('runtime pending location and stale RSSI cannot publish after disposal', (tester) async {
    SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
    final location = Completer<LatLng?>();
    final a = _Device('A')..connection.complete();
    final storage = _Storage();
    final service = _Service(_Bluetooth(), storage, {'A': a}, [], _Repository()..discovery.complete(), [],
        initializeRuntime: true, pollLocation: () => location.future);
    await tester.pump(); await service.runtimeReady;
    await service.connectToScooterId('A');
    a.rssiGate = Completer<int>();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    service.dispose();
    location.complete(const LatLng(9, 9)); a.rssiGate!.completeError(StateError('stale'));
    await tester.pump();
    expect(storage.scooters['A']!.lastLocation, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final sameId in [false, true]) {
    testWidgets('runtime obsolete resume RSSI failure cannot disconnect ${sameId ? 'same-ID replacement' : 'B'}', (tester) async {
      SharedPreferencesAsyncPlatform.instance = _RuntimePreferences();
      final a = _Device('A')..connection.complete();
      final devices = {'A': a};
      final service = _Service(_Bluetooth(), _Storage(), devices, [], _Repository()..discovery.complete(), [],
          initializeRuntime: true);
      await tester.pump(); await service.runtimeReady;
      await service.connectToScooterId('A');
      a.rssiGate = Completer<int>();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(a.rssiReads, 1);
      final id = sameId ? 'A' : 'B';
      final replacement = _Device(id)..connection.complete();
      devices[id] = replacement;
      if (sameId) { a.linked = false; service.connected = false; }
      final connecting = service.connectToScooterId(id);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await connecting;
      a.rssiGate!.completeError(StateError('obsolete suspended link'));
      await tester.pump();
      expect(service.connected, isTrue);
      expect(service.currentScooterId, id);
      expect(replacement.timeouts, hasLength(1));
      service.dispose(); await tester.pump();
    });
  }

  for (final action in ['lock', 'unlock', 'openseat']) {
    test('preissue missing command characteristic retains $action despite connected partial discovery', () async {
      final h = _WidgetHarness(); addTearDown(h.dispose);
      h.service.setManualConnectionTarget('A');
      final command = h.repoA.commandCharacteristic as _Characteristic;
      h.repoA.commandCharacteristic = null;
      await h.pending(action);
      await background.executeWidgetAction(action);
      expect(h.service.connected, isTrue);
      expect(command.writes, isEmpty);
      await h.expectPending(action);
    });
  }
  for (final operation in ['claim', 'reload3', 'remove']) {
    for (final throwsError in [true, false]) {
      if (operation.startsWith('reload') && !throwsError) continue; // reload returns void, not bool.
      for (final applied in [false, true]) {
        if (operation.startsWith('reload') && applied) continue;
        test('preissue $operation failure throws=$throwsError applied=$applied retains request without write', () async {
          final h = _WidgetHarness(); addTearDown(h.dispose);
          h.service.setManualConnectionTarget('A');
          final prefs = _ClaimPreferences();
          SharedPreferencesStorePlatform.instance = prefs;
          await h.pending('unlock'); prefs.arm();
          prefs.failures[operation] = throwsError;
          if (applied) prefs.afterPersistence.add(operation);
          await background.executeWidgetAction('unlock');
          expect(h.writes('A'), isEmpty);
          await h.expectPending('unlock');
          await background.executeWidgetAction('unlock');
          expect(h.writes('A'), ['scooter:state unlock']);
          await h.expectPending(null);
        });
      }
    }
  }

  for (final action in ['lock', 'unlock', 'openseat']) {
    for (final phase in ['reload2', 'remove', 'transport']) {
      test('preissue $action rechecks command readiness at $phase and retains known non-write', () async {
        final h = _WidgetHarness(); addTearDown(h.dispose);
        h.service.setManualConnectionTarget('A');
        final command = h.repoA.commandCharacteristic as _Characteristic;
        final prefs = _ClaimPreferences(); SharedPreferencesStorePlatform.instance = prefs;
        await h.pending(action); prefs.arm();
        prefs.after = (operation) async {
          if (operation == (phase == 'transport' ? 'remove' : phase)) {
            if (phase == 'transport') { h.a.forceDisconnected = true; }
            else { h.repoA.commandCharacteristic = null; }
          }
        };
        await background.executeWidgetAction(action);
        expect(command.writes, isEmpty);
        await h.expectPending(action);
        if (phase == 'reload2') expect(prefs.calls, isNot(contains('claim')));
      });
    }
  }
  for (final phase in ['claim', 'remove', 'restoreName']) {
    for (final armed in [true, false]) {
      test('preissue recovery at $phase preserves newer distinct request armed=$armed', () async {
        final h = _WidgetHarness(); addTearDown(h.dispose);
        h.service.setManualConnectionTarget('A');
        final prefs = _ClaimPreferences(); SharedPreferencesStorePlatform.instance = prefs;
        await h.pending('unlock'); prefs.arm();
        // Restore-name only runs after an applied removal with an uncertain result.
        if (phase == 'restoreName') {
          prefs.failures['remove'] = true; prefs.afterPersistence.add('remove');
        } else { prefs.failures[phase] = true; prefs.afterPersistence.add(phase); }
        prefs.after = (operation) async {
          if (operation == phase) await prefs.replaceWith('lock', armed: armed);
        };
        await background.executeWidgetAction('unlock');
        expect(h.writes('A'), isEmpty);
        final disk = await prefs.getAll();
        expect(disk['flutter.pendingWidgetAction'], armed);
        expect(disk['flutter.pendingWidgetActionName'], 'lock');
        if (phase == 'claim') expect(prefs.calls, isNot(contains('remove')));
      });
    }
  }
  for (final phase in ['reload4', 'restoreName', 'reload5', 'restoreFlag']) {
    for (final throwsError in [true, false]) {
      if (phase.startsWith('reload') && !throwsError) continue;
      test('preissue recovery $phase failure throws=$throwsError is bounded and reported honestly', () async {
        final h = _WidgetHarness(); addTearDown(h.dispose);
        h.service.setManualConnectionTarget('A');
        final prefs = _ClaimPreferences(); SharedPreferencesStorePlatform.instance = prefs;
        await h.pending('unlock'); prefs.arm();
        prefs.failures['remove'] = true; prefs.afterPersistence.add('remove');
        prefs.failures[phase] = throwsError;
        final warnings = <LogRecord>[];
        final listener = Logger('bgservice').onRecord.listen(warnings.add);
        addTearDown(listener.cancel);
        await background.executeWidgetAction('unlock');
        expect(h.writes('A'), isEmpty);
        expect(prefs.calls.where((call) => call == phase), hasLength(1));
        expect(warnings.where((record) => record.message.contains('Could not restore unissued action')), hasLength(1));
        final disk = await prefs.getAll();
        expect(disk['flutter.pendingWidgetAction'], isFalse);
        await background.executeWidgetAction('unlock'); // Unarmed: not silently retried.
        expect(h.writes('A'), isEmpty);
      });
    }
  }
  for (final replacement in ['pin', 'dispose', 'B', 'same-ID']) {
    for (final phase in ['claim', 'remove']) {
    test('preissue $replacement during awaited $phase restores without stale dispatch', () async {
      final h = _WidgetHarness();
      if (replacement != 'dispose') addTearDown(h.dispose);
      h.service.setManualConnectionTarget('A');
      final prefs = _ClaimPreferences(); SharedPreferencesStorePlatform.instance = prefs;
      await h.pending('unlock'); prefs.arm();
      prefs.after = (operation) async {
        if (operation != phase) return;
        switch (replacement) {
          case 'pin': h.service.setManualConnectionTarget('B');
          case 'dispose': h.dispose();
          case 'B': await h.service.connectToScooterId('B');
          case 'same-ID':
            h.a.linked = false; h.service.connected = false;
            h.a.connections.add(Completer<void>()..complete());
            await h.service.connectToScooterId('A');
        }
      };
      await background.executeWidgetAction('unlock');
      expect(h.writes('A'), isEmpty); expect(h.writes('B'), isEmpty);
      await h.expectPending('unlock');
      if (phase == 'claim') expect(prefs.calls, isNot(contains('remove')));
    });
    }
  }
  for (final action in ['lock', 'openseat']) {
    test('preissue $action possible native write error stays consumed with no automatic replay', () async {
      final h = _WidgetHarness(); addTearDown(h.dispose);
      h.service.setManualConnectionTarget('A');
      final command = h.repoA.commandCharacteristic as _Characteristic;
      command.failWrite = true;
      await h.pending(action);
      await background.executeWidgetAction(action);
      expect(command.writes, hasLength(1)); await h.expectPending(null);
      await background.executeWidgetAction(action);
      expect(command.writes, hasLength(1));
    });
  }

}
