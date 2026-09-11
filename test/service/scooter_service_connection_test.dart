import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:scooter_core/scooter_core.dart';
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
  Completer<void>? loadGate;
  @override
  SavedScooter? getMostRecent() => scooters.values.firstOrNull;
  final List<String> additions = [];
  final List<String> pings = [];

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
    linked = false;
  }
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic(this.bytes);
  final List<int> bytes;
  final values = StreamController<List<int>>.broadcast();
  int reads = 0;
  int notifications = 0;
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

// Linux exercises real connection and characteristic subscription wiring, but
// not Android bonding/priority or iOS widgets. Location is injected explicitly.
void main() {
  late SharedPreferencesAsyncPlatform? previousPreferences;
  late MemoryPreferences preferences;
  late _Storage storage;
  late _Bluetooth bluetooth;
  late Map<String, _Device> devices;
  late List<_Device> allDevices;

  _Device makeDevice(String id, [_Transport? transport]) {
    final device = _Device(id, transport);
    allDevices.add(device);
    return device;
  }

  late _Repository repository;
  late List<String> deviceRequests;
  late List<BluetoothDevice> repositories;
  late _Service service;
  late List<Future<Object?>> attempts;
  late List<Completer<LatLng?>> locations;
  bool disposed = false;

  Future<void> drain() => Future<void>.delayed(Duration.zero);
  Future<Object?> connect(String id) {
    // Install an error handler immediately, including for teardown failures.
    final result =
        service.connectToScooterId(id).then<Object?>((_) => null, onError: (Object error, StackTrace _) => error);
    attempts.add(result);
    return result;
  }

  setUp(() {
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    preferences = MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = preferences;
    storage = _Storage();
    bluetooth = _Bluetooth();
    allDevices = [];
    devices = {'A': makeDevice('A'), 'B': makeDevice('B')};
    repository = _Repository();
    deviceRequests = [];
    repositories = [];
    attempts = [];
    locations = [];
    disposed = false;
  });

  tearDown(() async {
    // Resolve only futures that have listeners. Drain before disposing so even
    // assertion failures cannot strand a connection or notify after disposal.
    // Let immediate requests reach their controlled await before enumerating
    // listeners. The registry retains replaced wrappers as well as reused ones.
    await drain();
    for (final device in allDevices) {
      for (final connection in device.connections.take(device.timeouts.length)) {
        if (!connection.isCompleted) {
          connection.completeError(StateError('teardown connection'));
        }
      }
    }
    if (repository.requests.isNotEmpty && !repository.discovery.isCompleted) {
      repository.discovery.completeError(StateError('teardown discovery'));
    }
    await Future.wait(attempts);
    await drain();
    if (!disposed) service.dispose();
    for (final location in locations) {
      if (!location.isCompleted) location.complete(null);
    }
    await drain();
    for (final device in allDevices) {
      expect(device.states.hasListener, isFalse);
      await device.states.close();
    }
    for (final characteristic in repository.characteristics) {
      expect(characteristic.values.hasListener, isFalse);
      await characteristic.values.close();
    }
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
  });

  void createService({Future<LatLng?> Function()? pollLocation}) {
    service =
        _Service(bluetooth, storage, devices, deviceRequests, repository, repositories, pollLocation: pollLocation);
  }

  Future<LatLng?> pendingLocation() {
    final result = Completer<LatLng?>();
    locations.add(result);
    return result.future;
  }

  Future<void> finishConnection(Future<Object?> attempt, _Device device) async {
    device.connections.last.complete();
    await drain();
    if (!repository.discovery.isCompleted) repository.discovery.complete();
    expect(await attempt, isNull); // Includes the real connect method's finally.
    await drain();
    expect(service.connected, isTrue);
    expect(service.connectingScooterId, isNull);
    expect(service.myScooter, same(device));
    expect(device.states.hasListener, isTrue);
    expect(repository.completenessChecks, greaterThan(0));
    expect(repository.anyAreNull(), isFalse);
    expect(service.vehicle.vehicleState, ScooterVehicleState.parked);
    expect(service.battery.primarySOC, 90);
    expect(service.identity.nrfVersion, 'test-firmware');
    expect(service.identity.odometerMeters, 123);
  }

  test('production adapter never restores cached protection and resets before B linking', () async {
    storage.scooters['A']!.handlebarsLocked = true;
    storage.scooters['B']!.handlebarsLocked = true;
    repository.alarmStatusCharacteristic = repository.characteristic('armed'.codeUnits);
    repository.alarmLastTriggerCharacteristic =
        repository.characteristic('motion,2026-01-02T03:04:05Z'.codeUnits);
    repository.alarmWakeSourcesCharacteristic = repository.characteristic([1, 3, 60, 0, 0, 0]);
    createService();
    await service.runtime.refetchSavedScooters();
    expect(service.handlebarsLocked, isNull);
    final a = connect('A');
    await drain();
    expect(service.handlebarsLocked, isNull);
    await finishConnection(a, devices['A']!);
    expect(service.handlebarsLocked, true);
    expect(service.vehicle.alarmStatus, AlarmStatus.armed);
    expect(service.vehicle.alarmLastTrigger, isNotNull);
    expect(service.vehicle.alarmWakeSources, isNotNull);
    final b = connect('B');
    // Invalidation is synchronous, before linking/discovery can publish B.
    expect(service.handlebarsLocked, isNull);
    expect(service.vehicle.alarmStatus, isNull);
    expect(service.vehicle.alarmLastTrigger, isNull);
    expect(service.vehicle.alarmWakeSources, isNull);
    await drain();
    expect(service.handlebarsLocked, isNull);
    await finishConnection(b, devices['B']!);
    expect(service.handlebarsLocked, true);
  });

  test('production adapter delayed cache load cannot overwrite fresh protection', () async {
    storage.scooters['A']!.handlebarsLocked = true;
    createService();
    final gate = Completer<void>();
    storage.loadGate = gate;
    final cache = service.runtime.refetchSavedScooters();
    final a = connect('A');
    await drain();
    await finishConnection(a, devices['A']!);
    final handlebar = repository.handlebarCharacteristic! as _Characteristic;
    handlebar.values.add('unlocked'.codeUnits);
    await drain();
    expect(service.handlebarsLocked, false);
    storage.scooters['A']!.handlebarsLocked = true;
    gate.complete();
    await cache;
    expect(service.handlebarsLocked, false);
    handlebar.values.add(<int>[]);
    await drain();
    expect(service.handlebarsLocked, isNull);
    expect(service.connected, true);
  });

  for (final reuseWrapper in [false, true]) {
    for (final olderSucceeds in [false, true]) {
      test(
          'same ID ${reuseWrapper ? 'reused wrapper' : 'distinct wrappers'}: '
          'older ${olderSucceeds ? 'success' : 'failure'} preserves fully connected newer session', () async {
        createService();
        final oldDevice = devices['A']!;
        final older = connect('A');
        await drain();
        final newDevice = reuseWrapper ? oldDevice : makeDevice('A', oldDevice.transport);
        devices['A'] = newDevice;
        final newer = connect('A');
        await drain();
        await finishConnection(newer, newDevice);
        final state = service.state;
        final failure = StateError('late older connection failure');
        if (olderSucceeds) {
          oldDevice.connection.complete();
        } else {
          oldDevice.connection.completeError(failure);
        }
        expect(await older, olderSucceeds ? isNull : same(failure));
        expect(service.connected, isTrue);
        expect(service.myScooter, same(newDevice));
        expect(service.connectingScooterId, isNull);
        expect(service.state, state);
        expect(oldDevice.transport.disconnects, 0);
        expect(newDevice.isConnected, isTrue);
        expect(newDevice.cancels, 0);
        expect(repositories, [same(newDevice)]);
      });
    }
  }

  test('different ID: late older success disconnects only itself after newer finally', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    await finishConnection(newer, devices['B']!);
    devices['A']!.connection.complete();
    expect(await older, isNull);
    expect(devices['A']!.disconnects, 1);
    expect(devices['A']!.linked, isFalse);
    expect(devices['B']!.disconnects, 0);
    expect(devices['B']!.linked, isTrue);
    expect(service.connected, isTrue);
    expect(service.myScooter, same(devices['B']));
    expect(service.connectingScooterId, isNull);
  });

  test('obsolete disconnect stream is cancelled; current disconnect clears connected', () async {
    createService();
    final first = connect('A');
    await drain();
    await finishConnection(first, devices['A']!);
    final second = connect('B');
    await drain();
    await finishConnection(second, devices['B']!);
    expect(devices['A']!.listens, 1);
    expect(devices['A']!.cancels, 1);
    expect(devices['A']!.states.hasListener, isFalse);
    final currentState = service.state;
    devices['A']!.emitDisconnected();
    await drain();
    expect(service.connected, isTrue);
    expect(service.state, currentState);
    expect(service.myScooter, same(devices['B']));
    expect(storage.pings, isEmpty);
    devices['B']!.emitDisconnected();
    await drain();
    expect(service.connected, isFalse);
    expect(service.state, ScooterState.disconnected);
    expect(storage.pings, ['B']);
  });

  test('current location result writes only the connected scooter', () async {
    createService(pollLocation: pendingLocation);
    final attempt = connect('B');
    await drain();
    await finishConnection(attempt, devices['B']!);
    const position = LatLng(3, 4);
    locations.single.complete(position);
    await drain();
    expect(storage.scooters['A']!.lastLocation, isNull);
    expect(storage.scooters['B']!.lastLocation, position);
  });

  test('superseded location result writes neither scooter; current result writes only B', () async {
    createService(pollLocation: pendingLocation);
    final first = connect('A');
    await drain();
    await finishConnection(first, devices['A']!);
    final second = connect('B');
    await drain();
    await finishConnection(second, devices['B']!);
    expect(locations, hasLength(2));
    locations[0].complete(const LatLng(1, 2));
    await drain();
    expect(storage.scooters['A']!.lastLocation, isNull);
    expect(storage.scooters['B']!.lastLocation, isNull,
        reason: 'A location must not be attributed to the newer B session');
    const currentPosition = LatLng(3, 4);
    locations[1].complete(currentPosition);
    await drain();
    expect(storage.scooters['A']!.lastLocation, isNull);
    expect(storage.scooters['B']!.lastLocation, currentPosition);
  });

  test('pending location result after disconnect is ignored', () async {
    createService(pollLocation: pendingLocation);
    final attempt = connect('A');
    await drain();
    await finishConnection(attempt, devices['A']!);
    expect(locations, hasLength(1));
    devices['A']!.emitDisconnected();
    await drain();
    expect(service.connected, isFalse);
    locations.single.complete(const LatLng(1, 2));
    await drain();
    expect(storage.scooters['A']!.lastLocation, isNull);
    expect(storage.scooters['B']!.lastLocation, isNull);
  });

  test('disposal during replacement cleans the older published transport', () async {
    createService();
    final older = connect('A');
    await drain();
    devices['A']!.connection.complete();
    await drain();
    expect(service.myScooter, same(devices['A']));
    expect(repository.requests, [true]);

    final replacement = connect('B');
    service.dispose();
    disposed = true;
    await drain();
    repository.discovery.completeError(StateError('late discovery failure'));
    await older;
    await replacement;
    expect(devices['A']!.isConnected, isFalse);
    expect(devices['A']!.disconnects, 1);
    expect(devices['B']!.timeouts, isEmpty);
  });

  test('connection completing after disposal releases its late transport', () async {
    createService();
    final pending = connect('A');
    await drain();
    service.dispose();
    disposed = true;
    devices['A']!.connection.complete();
    expect(await pending, isNull);
    expect(devices['A']!.isConnected, isFalse);
    expect(devices['A']!.disconnects, 1);
    expect(service.myScooter, isNull);
    expect(repository.requests, isEmpty);
  });

  test('runtime-disabled construction does not restore, scan or create timers', () async {
    int timers = 0;
    runZoned(createService,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            timers++;
            return parent.createTimer(zone, duration, callback);
          },
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            timers++;
            return parent.createPeriodicTimer(zone, duration, callback);
          },
        ));
    await drain();
    expect(service.store, same(storage));
    expect(service.settings, isNotNull);
    expect(service.scanner, isNotNull);
    expect(storage.loads, 0);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(bluetooth.scanStreamReads, 0);
    expect(bluetooth.stops, 0);
    expect(deviceRequests, isEmpty);
    expect(timers, 0);
    expect(service.state, ScooterState.disconnected);
    // tearDown also verifies disposal without initialized runtime timers.
  });

  test('manual target publishes intent and linking for the selected row', () async {
    createService();
    devices['A']!.linked = true;
    service.myScooter = devices['A'];
    service.connected = true;
    final linkingRows = <String?>[];
    service.addListener(() {
      if (service.state == ScooterState.linking) {
        linkingRows.add(service.connectingScooterId);
        expect(service.myScooter, isNull);
      }
    });
    final attempt = connect('B');
    await drain();
    expect(
        service.updates,
        contains(equals({
          'manualConnectionTarget': 'B',
          'scooterName': 'Beta',
          'scooterColor': 2,
        })));
    expect(linkingRows, isNotEmpty);
    expect(linkingRows, everyElement('B'));
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.scooterName, 'Beta');
    expect(service.connected, isFalse);
    expect(devices['A']!.disconnects, 1);
    expect(devices['B']!.timeouts, [const Duration(seconds: 30)]);
    expect(bluetooth.stops, 1);
    final failure = StateError('B unavailable');
    devices['B']!.connection.completeError(failure);
    expect(await attempt, same(failure));
    expect(service.state, ScooterState.disconnected);
    expect(service.connectingScooterId, isNull);
  });

  test('obsolete automatic generation is rejected after a manual intent', () async {
    createService();
    final manual = connect('B');
    await drain();
    final updates = service.updates.length;
    // A newly constructed service starts at generation zero; a manual request
    // invalidates a startup auto-connect carrying that original generation.
    await service.connectToScooterId('A', automatic: true, expectedIntentGeneration: 0);
    expect(deviceRequests, ['B']);
    expect(devices['A']!.timeouts, isEmpty);
    expect(service.updates.length, updates);
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.myScooter, isNull);
    devices['B']!.connection.completeError(StateError('B unavailable'));
    expect(await manual, isA<StateError>());
  });

  test('late older failure preserves newer linking attempt', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    final failure = StateError('late A failure');
    devices['A']!.connection.completeError(failure);
    expect(await older, same(failure));
    expect(deviceRequests, ['A', 'B']);
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(service.myScooter, isNull);
    expect(devices['B']!.disconnects, 0);
    devices['B']!.connection.completeError(StateError('B unavailable'));
    expect(await newer, isA<StateError>());
    expect(service.state, ScooterState.disconnected);
  });

  test('late older success disconnects only its own different-ID transport', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    devices['B']!.connection.complete();
    await drain();
    expect(repositories, [same(devices['B'])]);
    devices['A']!.connection.complete();
    expect(await older, isNull);
    expect(devices['A']!.disconnects, 1);
    expect(devices['B']!.disconnects, 0);
    expect(devices['B']!.isConnected, isTrue);
    expect(service.myScooter, same(devices['B']));
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    repository.discovery.completeError(StateError('controlled discovery failure'));
    expect(await newer, isA<StateError>());
  });

  for (final reuseWrapper in [false, true]) {
    for (final olderSucceeds in [false, true]) {
      test(
          'same ID ${reuseWrapper ? 'reused wrapper' : 'distinct wrappers'}: '
          'older ${olderSucceeds ? 'success' : 'failure'} preserves newer discovery', () async {
        createService();
        final oldDevice = devices['A']!;
        final older = connect('A');
        await drain();
        final newDevice = reuseWrapper ? oldDevice : makeDevice('A', oldDevice.transport);
        devices['A'] = newDevice;
        final newer = connect('A');
        await drain();
        newDevice.connections.last.complete();
        await drain();
        expect(repositories, [same(newDevice)]);
        expect(repository.requests, [true]);
        expect(service.myScooter, same(newDevice));
        final failure = StateError('older A connection failed');
        if (olderSucceeds) {
          oldDevice.connection.complete();
        } else {
          oldDevice.connection.completeError(failure);
        }
        expect(await older, olderSucceeds ? isNull : same(failure));
        expect(service.myScooter, same(newDevice));
        expect(service.connectingScooterId, 'A');
        expect(service.state, ScooterState.linking);
        expect(oldDevice.transport.disconnects, 0,
            reason: 'Stale wrapper cleanup must not disconnect the newer same-ID physical link');
        expect(newDevice.isConnected, isTrue);
        repository.discovery.completeError(StateError('controlled discovery failure'));
        expect(await newer, isA<StateError>());
      });
    }
  }

  for (final olderSucceeds in [false, true]) {
    test(
        'reused wrapper: two stale ${olderSucceeds ? 'successes' : 'failures'} '
        'must not relinquish newest discovery ownership', () async {
      createService();
      final device = devices['A']!;
      final first = connect('A');
      await drain();
      final second = connect('A');
      await drain();
      final newest = connect('A');
      await drain();
      expect(device.connections, hasLength(3));
      device.connections[2].complete();
      await drain();
      expect(repositories, [same(device)]);
      expect(service.myScooter, same(device));
      for (var index = 0; index < 2; index++) {
        final failure = StateError('stale connection $index');
        if (olderSucceeds) {
          device.connections[index].complete();
        } else {
          device.connections[index].completeError(failure);
        }
        expect(await [first, second][index], olderSucceeds ? isNull : same(failure));
        expect({
          'disconnects': device.disconnects,
          'ownsNewestDevice': identical(service.myScooter, device),
          'physicalLinkConnected': device.isConnected,
        }, {
          'disconnects': 0,
          'ownsNewestDevice': true,
          'physicalLinkConnected': true
        }, reason: 'Stale completion $index must not clear the newest attempt ownership');
        expect(service.connectingScooterId, 'A');
        expect(service.state, ScooterState.linking);
      }
      repository.discovery.completeError(StateError('controlled discovery failure'));
      expect(await newest, isA<StateError>());
    });
  }

  test('immediate A/B overlap never publishes obsolete A after B intent', () async {
    createService();
    final linkingRows = <String?>[];
    service.addListener(() {
      if (service.state == ScooterState.linking) linkingRows.add(service.connectingScooterId);
    });
    final older = connect('A');
    final newer = connect('B'); // No drain: both are awaiting initial cancellation.
    await drain();
    expect(
        service.updates
            .where((update) => update.containsKey('manualConnectionTarget'))
            .map((update) => update['manualConnectionTarget']),
        ['A', 'B']);
    expect(await older, isNull);
    expect(devices['A']!.timeouts, isEmpty);
    expect(service.connectingScooterId, 'B');
    expect(linkingRows, isNotEmpty);
    expect(linkingRows, everyElement('B'),
        reason: 'A resumed after B intent and must not publish obsolete linking state');
    devices['B']!.connection.completeError(StateError('controlled B failure'));
    expect(await newer, isA<StateError>());
  });

  test('late older failure preserves newer device during repository discovery', () async {
    createService();
    final older = connect('A');
    await drain();
    final newer = connect('B');
    await drain();
    devices['B']!.connection.complete();
    await drain();
    expect(repositories, [same(devices['B'])]);
    expect(repository.requests, [true]);
    expect(storage.additions, ['B']);
    expect(service.myScooter, same(devices['B']));
    devices['A']!.connection.completeError(StateError('late A failure'));
    expect(await older, isA<StateError>());
    expect(service.myScooter, same(devices['B']));
    expect(service.connectingScooterId, 'B');
    expect(service.state, ScooterState.linking);
    expect(devices['B']!.disconnects, 0);
    final failure = StateError('controlled discovery failure');
    repository.discovery.completeError(failure);
    expect(await newer, same(failure));
    expect(service.myScooter, isNull);
    expect(service.state, ScooterState.disconnected);
    expect(preferences.writes, 0);
  });
}
