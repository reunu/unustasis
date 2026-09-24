import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:unustasis/background/bg_service.dart' as background;
import 'package:unustasis/background/notification_handler.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/statistics_helper.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

// Local fake-only consumer harness: the frozen 87-case import stays untouched.
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
  Completer<int>? rssiGate;
  @override
  Future<int> readRssi({int timeout = 15}) async {
    rssiReads++;
    if (rssiGate != null) return rssiGate!.future;
    if (silentFailure) throw StateError('Silent disconnect');
    return -70;
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

  late List<LogRecord> warnings;
  setUp(() {
    warnings = [];
    // Isolate this category so a reentrant runtime info log is not published
    // back into the same synchronous root stream controller.
    final wasHierarchical = hierarchicalLoggingEnabled;
    hierarchicalLoggingEnabled = true;
    addTearDown(() => hierarchicalLoggingEnabled = wasHierarchical);
    final subscription = Logger('ScooterService').onRecord.listen((record) {
      if (record.level == Level.WARNING && record.message == 'Locking with open seatbox!') {
        warnings.add(record);
      }
    });
    addTearDown(subscription.cancel);
  });

  Future<_WidgetHarness> ready({bool? seatClosed = false}) async {
    final h = _WidgetHarness();
    addTearDown(h.dispose);
    await h.service.connectToScooterId('A');
    h.service.vehicle.seatClosed = seatClosed;
    return h;
  }

  for (final producer in ['widget', 'notification']) {
    test('$producer open-seat lock warns once at dispatch, not at persistence or replay', () async {
      final h = await ready();
      if (producer == 'notification') {
        await notificationTapBackground(const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'lock',
        ));
        final messages = FlutterBackgroundServicePlatform.instance as RecordingBackgroundService;
        expect(messages.updates.last['method'], 'lock');
      } else {
        await h.pending('lock');
      }
      expect(warnings, isEmpty);
      final command = h.repoA.commandCharacteristic as _Characteristic;
      command.writeGate = Completer<void>();
      final action = background.executeWidgetAction('lock');
      await Future<void>.delayed(Duration.zero);
      expect(h.writes('A'), ['scooter:state lock']);
      // Diagnostic precedes acknowledgment, even when that acknowledgment waits.
      final beforeAck = warnings.toList();
      command.writeGate!.complete();
      await action;
      expect(beforeAck, hasLength(1));
      expect(warnings.single.loggerName, 'ScooterService');
      await h.expectPending(null);
      await background.executeWidgetAction('lock');
      expect(warnings, hasLength(1));
      expect(h.writes('A'), hasLength(1));
      expect(h.writes('B'), isEmpty);
    });
  }

  test('ordinary facade lock has exactly one open-seat warning', () async {
    final h = await ready();
    await h.service.lock(checkHandlebars: false);
    expect(warnings, hasLength(1));
    expect(warnings.single.loggerName, 'ScooterService');
    expect(h.writes('A'), ['scooter:state lock']);
  });

  for (final action in ['unlock', 'openseat', 'unknown']) {
    test('$action with open seat does not warn about locking', () async {
      final h = await ready();
      await h.pending(action);
      await background.executeWidgetAction(action);
      expect(warnings, isEmpty);
      expect(h.writes('A'), action == 'unknown' ? isEmpty : hasLength(1));
    });
  }

  for (final closed in [true, null]) {
    test('lock with seatClosed=$closed does not warn', () async {
      final h = await ready(seatClosed: closed);
      await h.pending('lock');
      await background.executeWidgetAction('lock');
      expect(warnings, isEmpty);
      expect(h.writes('A'), ['scooter:state lock']);
    });
  }

  test('passive and merely prepared lock do not warn or write', () async {
    final h = await ready();
    await h.service.attemptLatestAutoConnection();
    expect(await h.service.prepareWidgetAction('lock'), isNotNull);
    await background.executeWidgetAction('lock'); // No persisted request.
    expect(warnings, isEmpty);
    expect(h.writes('A'), isEmpty);
  });

  test('deferred lock during pending connection does not warn', () async {
    final h = _WidgetHarness(holdA: true);
    addTearDown(h.dispose);
    h.service.vehicle.seatClosed = false;
    h.service.setManualConnectionTarget('A');
    final connection = h.service.connectToScooterId('A', automatic: true);
    await Future<void>.delayed(Duration.zero);
    await h.pending('lock');
    await background.executeWidgetAction('lock');
    expect(warnings, isEmpty);
    expect(h.writes('A'), isEmpty);
    await h.expectPending('lock');
    h.a.connection.complete();
    await connection;
  });

  test('missing command retains lock without misleading warning', () async {
    final h = await ready();
    final command = h.repoA.commandCharacteristic as _Characteristic;
    h.repoA.commandCharacteristic = null;
    await h.pending('lock');
    await background.executeWidgetAction('lock');
    expect(warnings, isEmpty);
    expect(command.writes, isEmpty);
    await h.expectPending('lock');
  });

  test('stale dispatch after claim does not warn or retarget writes', () async {
    final h = await ready();
    final prefs = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = prefs;
    await h.pending('lock');
    prefs.onRemove = () => h.service.setManualConnectionTarget('B');
    await background.executeWidgetAction('lock');
    expect(warnings, isEmpty);
    expect(h.writes('A'), isEmpty);
    expect(h.writes('B'), isEmpty);
    await h.expectPending('lock');
  });

  for (final effect in ['pin', 'connection', 'command']) {
    test('reentrant warning $effect invalidation cannot write or retarget', () async {
      final h = await ready();
      final command = h.repoA.commandCharacteristic as _Characteristic;
      Future<void>? replacement;
      final subscription = Logger('ScooterService').onRecord.listen((record) {
        if (record.message != 'Locking with open seatbox!') return;
        switch (effect) {
          case 'pin':
            h.service.setManualConnectionTarget('B');
          case 'connection':
            replacement = h.service.connectToScooterId('B');
          case 'command':
            h.repoA.commandCharacteristic = null;
        }
      });
      addTearDown(subscription.cancel);
      await h.pending('lock');
      await background.executeWidgetAction('lock');
      await replacement;
      expect(warnings, hasLength(1));
      expect(command.writes, isEmpty);
      expect(h.writes('B'), isEmpty);
      await h.expectPending('lock');
    });
  }
}
