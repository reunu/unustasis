import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:unustasis/domain/nav_destination.dart';
import '../support/command_transport_fakes.dart';
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

final class _NavigationPreferences extends SharedPreferencesAsyncPlatform {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async => values[key];
  @override
  Future<void> setString(String key, String value, SharedPreferencesOptions options) async {
    values[key] = value;
  }

  @override
  Future<void> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) async {
    values.removeWhere((key, _) => parameters.filter.allowList?.contains(key) ?? true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

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
    SharedPreferencesAsyncPlatform.instance = _NavigationPreferences();
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
  });
  for (final transition in ['new request', 'replacement', 'same-ID', 'disconnect']) {
    test('pending navigation rejects old ACK after $transition', () async {
      final old = _Device('A')..connection.complete();
      final next = _Device(transition == 'same-ID' ? 'A' : 'B')..connection.complete();
      final devices = {'A': old, 'B': next};
      final repo = _Repository()..discovery.complete();
      repo.nrfVersionCharacteristic = repo.characteristic('1-ls'.codeUnits);
      final wire = TransportTestCharacteristic();
      repo.extendedCommandCharacteristic = repo.extendedResponseCharacteristic = wire;
      final held = Completer<void>();
      wire.onWrite = (write) async {
        if (write.command.startsWith('nav:dest')) await held.future;
        wire.reply(write.command.startsWith('nav:') ? 'nav:ok' : 'unsupported');
      };
      final service = _Service(_Bluetooth(), _Storage(), devices, [], repo, []);
      addTearDown(service.dispose);
      final first = NavDestination(location: const LatLng(1, 2), name: 'First');
      final newer = NavDestination(location: const LatLng(3, 4), name: 'New');
      await service.setPendingNavigation(first);
      await service.connectToScooterId('A');
      await Future<void>.delayed(Duration.zero);
      expect(wire.writes.where((w) => w.command.startsWith('nav:dest')), hasLength(1));
      if (transition == 'new request') {
        await service.setPendingNavigation(newer);
      } else if (transition == 'disconnect') {
        old.emitDisconnected();
      } else {
        // Hold the next firmware read so only A's old dispatch can publish.
        repo.nrfVersionCharacteristic = null;
        if (transition == 'same-ID') {
          old.emitDisconnected();
          await Future<void>.delayed(Duration.zero);
          devices['A'] = next;
        }
        await service.connectToScooterId(next.remoteId.str);
      }
      await Future<void>.delayed(Duration.zero);
      held.complete();
      await Future<void>.delayed(Duration.zero);
      expect(service.activeNavigation, isNull);
      expect(service.pendingNavigation?.name, transition == 'new request' ? 'New' : 'First');
      expect(wire.listeners, 0);
    });
  }
  test('facade pendingNavigation preference restores inferred name and removes invalid entries', () async {
    final preferences = SharedPreferencesAsyncPlatform.instance as _NavigationPreferences;
    preferences.values['unrelated'] = 'keep';
    final repo = _Repository()..discovery.complete();
    final service = _Service(_Bluetooth(), _Storage(), {}, [], repo, []);
    addTearDown(service.dispose);
    preferences.values['pendingNavigation'] = '{invalid';
    await service.navigation.restorePending();
    expect(preferences.values, {'unrelated': 'keep'});
    preferences.values['pendingNavigation'] = '{"latitude":1,"longitude":2,"name":"Home","id":"7"}';
    await service.navigation.restorePending();
    expect(service.pendingNavigation!.type, SpecialDestinationType.home);
    await service.setPendingNavigation(null);
    expect(preferences.values, {'unrelated': 'keep'});
  });
  test('actual firmware-ready dispatch activates and removes the captured persisted pending request', () async {
    final device = _Device('A')..connection.complete();
    final repo = _Repository()..discovery.complete();
    repo.nrfVersionCharacteristic = repo.characteristic('1-ls'.codeUnits);
    final wire = TransportTestCharacteristic();
    repo.extendedCommandCharacteristic = repo.extendedResponseCharacteristic = wire;
    wire.onWrite = (write) async => wire.reply(write.command.startsWith('nav:') ? 'nav:ok' : 'unsupported');
    final service = _Service(_Bluetooth(), _Storage(), {'A': device}, [], repo, []);
    addTearDown(service.dispose);
    final d = NavDestination(location: const LatLng(1, 2), name: 'Home');
    await service.setPendingNavigation(d);
    final preferences = SharedPreferencesAsyncPlatform.instance as _NavigationPreferences;
    expect(jsonDecode(preferences.values['pendingNavigation']!), d.toJson());
    await service.connectToScooterId('A');
    await Future<void>.delayed(Duration.zero);
    expect(service.activeNavigation!.toJson(), d.toJson());
    expect(service.pendingNavigation, isNull);
    expect(preferences.values.containsKey('pendingNavigation'), false);
    expect(wire.writes.where((w) => w.command.startsWith('nav:')).single.command, 'nav:dest 1.0,2.0,Home');
    expect(wire.listeners, 0);
  });
  for (final cancelSucceeds in [false, true]) {
    test('Unustasis active UI follows telemetry, not navigation ACK or cancel $cancelSucceeds', () async {
      final device = _Device('A')..connection.complete();
      final repo = _Repository()..discovery.complete();
      final navigationState = repo.characteristic([0]);
      repo.navigationActiveCharacteristic = navigationState;
      final wire = TransportTestCharacteristic();
      repo.extendedCommandCharacteristic = repo.extendedResponseCharacteristic = wire;
      wire.onWrite = (write) async => wire.reply(
          write.command == 'nav:clear' && !cancelSucceeds ? 'nav:error' : 'nav:ok');
      final service = _Service(_Bluetooth(), _Storage(), {'A': device}, [], repo, []);
      addTearDown(service.dispose);
      await service.connectToScooterId('A');
      await Future<void>.delayed(Duration.zero);
      expect(service.vehicle.navigationActive, false);
      final destination = NavDestination(location: const LatLng(1, 2), name: 'Home');
      await service.navigation.navigate(destination);
      expect(service.activeNavigation!.name, 'Home');
      expect(service.vehicle.navigationActive, false);
      navigationState.values.add([1]);
      await Future<void>.delayed(Duration.zero);
      expect(service.vehicle.navigationActive, true);
      await service.setPendingNavigation(destination);
      if (cancelSucceeds) {
        await service.navigation.cancel();
      } else {
        await expectLater(service.navigation.cancel(), throwsA(isA<String>()));
      }
      // Unlike Librescoot, the generic Unustasis card waits for scooter truth.
      expect(service.activeNavigation, isNull);
      expect(service.vehicle.navigationActive, true);
      expect(service.pendingNavigation!.name, 'Home');
      final preferences = SharedPreferencesAsyncPlatform.instance as _NavigationPreferences;
      expect(jsonDecode(preferences.values['pendingNavigation']!)['name'], 'Home');
      navigationState.values.add([0]);
      await Future<void>.delayed(Duration.zero);
      expect(service.vehicle.navigationActive, false);
      expect(wire.listeners, 0);
    });
  }

}
