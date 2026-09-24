import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/scooter_battery.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'telemetry_stale_reproduction_test.dart' show LateStream;

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic({List<int>? answer}) : _answer = answer;
  final List<int>? _answer;
  final values = LateStream();
  final reads = <Completer<List<int>>>[];
  @override
  Stream<List<int>> get lastValueStream => values;
  @override
  Stream<List<int>> get onValueReceived => values;
  @override
  Future<bool> setNotifyValue(bool notify,
          {int timeout = 15, bool forceIndications = false}) async =>
      true;
  @override
  Future<List<int>> read({int timeout = 15}) {
    // Some characteristics answer straight away; the rest are completed by the
    // test through [reads] so it can control the ordering.
    if (_answer != null) return Future.value(_answer);
    final gate = Completer<List<int>>();
    reads.add(gate);
    return gate.future;
  }

  void text(String value) => values.deliver(utf8.encode(value));
  void number(int value) => values.deliver(
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List());
}

class _Extended extends Fake implements BluetoothCharacteristic {
  final responses = StreamController<List<int>>.broadcast(sync: true);
  final writes = <String>[];
  int notifyWrites = 0;
  @override
  bool get isNotifying => true;
  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    notifyWrites++;
    return true;
  }

  @override
  Stream<List<int>> get onValueReceived => responses.stream;
  @override
  Future<void> write(List<int> bytes,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    expect(responses.hasListener, true);
    final command = ascii.decode(bytes);
    writes.add(command);
    if (command == 'cap:ext') {
      responses.add(ascii.encode('cap:ext:pm:config:ble:alarm'));
    } else if (command == 'cap:list') {
      responses.add(ascii.encode('cap:count:4'));
      responses.add(ascii.encode('cap:pm'));
      responses.add(ascii.encode('cap:config'));
      responses.add(ascii.encode('cap:ble'));
      responses.add(ascii.encode('cap:alarm'));
    } else if (command.startsWith('cap:')) {
      final feature = {'cap:ble': 'forget'}[command]!;
      responses.add(ascii.encode('$command:count:1'));
      responses.add(ascii.encode('$command:$feature'));
    } else {
      responses.add(ascii.encode('$command:'));
    }
  }
}

class _Device extends Fake implements BluetoothDevice {
  _Device(String id) : remoteId = DeviceIdentifier(id);
  @override
  final DeviceIdentifier remoteId;
  bool live = false;
  final states =
      StreamController<BluetoothConnectionState>.broadcast(sync: true);
  final servicesResets = StreamController<void>.broadcast(sync: true);
  @override
  bool get isConnected => live;
  @override
  bool get isDisconnected => !live;
  @override
  DisconnectReason? get disconnectReason => null;
  @override
  Stream<BluetoothConnectionState> get connectionState => states.stream;
  @override
  Stream<void> get onServicesReset => servicesResets.stream;
  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 35),
      int? mtu = 512,
      bool autoConnect = false}) async {
    live = true;
  }

  @override
  Future<void> disconnect(
      {int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    drop();
  }

  void drop() {
    live = false;
    states.add(BluetoothConnectionState.disconnected);
  }
}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  @override
  Future<void> stopScan() async {}
}

class _Repository extends CharacteristicRepository {
  _Repository(super.scooter,
      {bool optional = true, String? imxVersion = 'v1.15.0'}) {
    primarySOCCharacteristic = chars['primarySOC'] = _Characteristic();
    primaryCyclesCharacteristic = chars['primaryCycles'] = _Characteristic();
    secondarySOCCharacteristic = chars['secondarySOC'] = _Characteristic();
    secondaryCyclesCharacteristic =
        chars['secondaryCycles'] = _Characteristic();
    cbbSOCCharacteristic = chars['cbbSOC'] = _Characteristic();
    cbbVoltageCharacteristic = chars['cbbVoltage'] = _Characteristic();
    cbbCapacityCharacteristic = chars['cbbCapacity'] = _Characteristic();
    cbbChargingCharacteristic = chars['cbbCharging'] = _Characteristic();
    auxSOCCharacteristic = chars['auxSOC'] = _Characteristic();
    auxVoltageCharacteristic = chars['auxVoltage'] = _Characteristic();
    auxChargingCharacteristic = chars['auxCharging'] = _Characteristic();
    stateCharacteristic = chars['state'] = _Characteristic();
    seatCharacteristic = chars['seat'] = _Characteristic();
    handlebarCharacteristic = chars['handlebar'] = _Characteristic();
    nrfVersionCharacteristic = chars['nrfVersion'] = _Characteristic();
    imxVersionCharacteristic = imxVersion == null
        ? null
        : (chars['imxVersion'] =
            _Characteristic(answer: utf8.encode(imxVersion)));
    odometerCharacteristic = chars['odometer'] = _Characteristic();
    powerStateCharacteristic =
        optional ? (chars['powerState'] = _Characteristic()) : null;
    umsStatusCharacteristic =
        optional ? (chars['umsStatus'] = _Characteristic()) : null;
    navigationActiveCharacteristic =
        optional ? (chars['navigationActive'] = _Characteristic()) : null;
    alarmStatusCharacteristic =
        optional ? (chars['alarmStatus'] = _Characteristic()) : null;
    alarmLastTriggerCharacteristic =
        optional ? (chars['alarmLastTrigger'] = _Characteristic()) : null;
    alarmWakeSourcesCharacteristic =
        optional ? (chars['alarmWakeSources'] = _Characteristic()) : null;
    extendedCommandCharacteristic = null;
    extendedResponseCharacteristic = null;
  }
  final chars = <String, _Characteristic>{};
  _Characteristic operator [](String key) => chars[key]!;
  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {}
  @override
  bool anyAreNull() => false;
}

class _Effects implements ScooterTelemetryEffects {
  final trace = <String>[];
  final patches = <(String, TelemetryCachePatch)>[];
  final snapshots = <TelemetrySnapshot>[];
  final transitions = <(ScooterState?, ScooterState?)>[];
  void Function()? onChanged;
  void Function()? onCache;
  void Function()? onFirmware;
  @override
  void cachePatch(String id, TelemetryCachePatch patch) {
    patches.add((id, patch));
    trace.add('cache:$id');
    onCache?.call();
  }

  @override
  void ping(String id) => trace.add('ping:$id');
  @override
  void changed(TelemetrySnapshot snapshot) {
    snapshots.add(snapshot);
    trace.add('notify');
    onChanged?.call();
  }

  @override
  void firmwareIdentified(
      SessionConnection connection, FirmwareSnapshot firmware) {
    trace.add('firmware:${connection.id}:${firmware.isLibrescoot}');
    onFirmware?.call();
  }

  @override
  void navigationChanged(bool? active) => trace.add('navigation:$active');
  @override
  void aggregateTransition(ScooterState? previous, ScooterState? next) {
    transitions.add((previous, next));
    trace.add('aggregate');
  }

  @override
  void probeFailed(String message, Object error, StackTrace stack) =>
      trace.add('failed:$message');
}

class _SessionEffects implements ScooterSessionEffects {
  _SessionEffects(this.telemetry);
  final ScooterTelemetry telemetry;
  final tokens = <SessionConnection>[];
  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {}
  @override
  void invalidateTelemetry() => telemetry.invalidate();
  @override
  void linking(SessionConnection connection) =>
      telemetry.seed(const CachedTelemetry());
  @override
  void transportConnected(SessionConnection connection) {
    tokens.add(connection);
    telemetry.prepare(const CachedTelemetry());
  }

  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {}
  @override
  void wireTelemetry(
          SessionConnection connection, CharacteristicRepository repository) =>
      telemetry.bind(connection, repository);
  @override
  void readyMetadata(SessionConnection connection) {}
  @override
  void ready(SessionConnection connection) {}
  @override
  void disconnected(String? id) => telemetry.invalidate();
}

class _Harness {
  _Harness(
      {bool optional = true,
      bool defaultQueries = false,
      String? imxVersion = 'v1.15.0',
      Set<String> groups = const {'pm', 'config', 'ble', 'alarm'},
      Future<LsCapabilityGroups> Function()? capabilityGroups,
      Future<Set<String>> Function(String)? caps,
      Future<String?> Function(String)? setting,
      Future<void> Function(String key, String value)? settingWrite}) {
    telemetry = ScooterTelemetry(
        effects: effects,
        capabilities: defaultQueries
            ? null
            : (_, __, category, {isCurrent}) async {
                queries.add(category);
                return caps == null
                    ? {'hibernate-for', 'apn', 'forget', 'enable'}
                    : await caps(category);
              },
        setting: defaultQueries
            ? null
            : (_, __, key, {isCurrent}) async {
                queries.add(key);
                return setting == null ? '' : await setting(key);
              },
        settingWrite: defaultQueries
            ? null
            : (_, __, key, value, {isCurrent}) async {
                queries.add('set:$key:$value');
                await settingWrite?.call(key, value);
              },
        capabilityGroups: defaultQueries
            ? null
            : (_, __, {isCurrent}) async {
                queries.add('cap:ext');
                if (capabilityGroups != null) return capabilityGroups();
                try {
                  if (caps != null) await caps('cap:ext');
                  return LsCapabilityGroups(
                    {for (final group in groups) group: null},
                    usedFallback: false,
                  );
                } catch (_) {
                  return const LsCapabilityGroups({}, usedFallback: false);
                }
              });
    sessionEffects = _SessionEffects(telemetry);
    session = ScooterSession(
        flutterBluePlus: _Bluetooth(),
        effects: sessionEffects,
        onChanged: () {},
        findEligibleScooter: () async => null,
        isScanning: () => false,
        onStart: () {},
        isAndroid: false,
        isIOS: false,
        deviceFromId: (id) {
          final device = _Device(id);
          devices.add(device);
          return device;
        },
        repositoryFactory: (device) {
          final repo =
              _Repository(device, optional: optional, imxVersion: imxVersion);
          repositories.add(repo);
          return repo;
        });
  }
  final effects = _Effects();
  final devices = <_Device>[];
  final repositories = <_Repository>[];
  final queries = <String>[];
  late final ScooterTelemetry telemetry;
  late final ScooterSession session;
  late final _SessionEffects sessionEffects;
  Future<_Repository> connect(String id) async {
    await session.connectToScooterId(id);
    return repositories.last;
  }

  Future<void> dispose() async {
    session.dispose();
    telemetry.dispose();
    for (final device in devices) {
      await device.states.close();
      await device.servicesResets.close();
    }
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
void _firmware(_Repository repo, [String version = 'v2.13.0-ls']) =>
    repo['nrfVersion'].reads.single.complete(utf8.encode(version));
void _wireExtended(_Repository repo) {
  final channel = _Characteristic();
  repo.extendedCommandCharacteristic = repo.chars['extendedCommand'] = channel;
  repo.extendedResponseCharacteristic =
      repo.chars['extendedResponse'] = channel;
}

List<bool?> _caps(FirmwareIdentity identity) => [
      identity.supportsHibernateFor,
      identity.supportsScheduledHibernation,
      identity.supportsApnConfig,
      identity.supportsBondForget,
      identity.supportsBatteryKeepActive,
      identity.supportsAlarmControl,
      identity.supportsServiceMode,
      identity.supportsNavigation,
    ];
const _queryOrder = [
  'cap:ext',
  'pm.scheduled-hibernate-enabled',
  'scooter.battery-keep-active-on-seatbox-open',
];

void main() {
  for (final ending in [
    'B',
    'same-ID',
    'disconnect',
    'dispose',
    'invalidate'
  ]) {
    test(
        'all queued battery/vehicle callbacks and identity reads ignored after $ending',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final a = await h.connect('A');
      final old = h.sessionEffects.tokens.single;
      if (ending == 'B' || ending == 'same-ID') {
        if (ending == 'same-ID') {
          h.devices.single.drop();
        }
        await h.connect(ending == 'B' ? 'B' : 'A');
      } else if (ending == 'disconnect') {
        h.devices.single.drop();
      } else if (ending == 'dispose') {
        h.session.dispose();
      } else {
        h.telemetry.invalidate();
      }
      if (ending != 'invalidate') {
        expect(old.isCurrent, isFalse);
      }
      h.effects.trace.clear();
      final before = h.telemetry.snapshot;
      for (final entry in a.chars.entries) {
        entry.value.number(77);
        entry.value.text('open');
        entry.value.text('charging');
        entry.value.text('bulk-charge');
        entry.value.text('parked');
        entry.value.text('running');
        entry.value.values.deliver(List.filled(6, 0));
      }
      _firmware(a);
      a['odometer'].reads.single.complete([42, 0, 0, 0]);
      await _flush();
      final after = h.telemetry.snapshot;
      expect(after.battery.primarySOC, before.battery.primarySOC);
      expect(after.battery.secondarySOC, before.battery.secondarySOC);
      expect(after.battery.cbbSOC, before.battery.cbbSOC);
      expect(after.battery.auxSOC, before.battery.auxSOC);
      expect(after.battery.primaryCycles, isNull);
      expect(after.battery.secondaryCycles, isNull);
      expect(after.battery.cbbVoltage, isNull);
      expect(after.battery.cbbCapacity, isNull);
      expect(after.battery.cbbCharging, isNull);
      expect(after.battery.auxVoltage, isNull);
      expect(after.battery.auxCharging, isNull);
      expect(after.vehicle.seatClosed, isNull);
      expect(after.vehicle.handlebarsLocked, isNull);
      expect(after.vehicle.navigationActive, isNull);
      expect(after.vehicle.usbMode, isNull);
      expect(after.vehicle.vehicleState, isNull);
      expect(after.vehicle.powerState, isNull);
      expect(after.vehicle.alarmStatus, isNull);
      expect(after.vehicle.alarmLastTrigger, isNull);
      expect(after.vehicle.alarmWakeSources, isNull);
      expect(after.firmware.nrfVersion, isNull);
      expect(after.firmware.odometerMeters, isNull);
      expect(after.revision, before.revision);
      expect(h.effects.trace, isEmpty);
      expect(h.queries, isEmpty);
    });
  }

  for (final ending in ['B', 'same-ID', 'disconnect', 'dispose']) {
    test('populated protection resets immediately on $ending', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final a = await h.connect('A');
      a['handlebar'].text('locked');
      a['alarmStatus'].text('armed');
      a['alarmLastTrigger'].text('motion,2026-01-02T03:04:05Z');
      a['alarmWakeSources'].values.deliver([1, 3, 60, 0, 0, 0]);
      final before = h.telemetry.snapshot.vehicle;
      expect(before.handlebarsLocked, true);
      expect(before.alarmStatus, AlarmStatus.armed);
      expect(before.alarmLastTrigger, isNotNull);
      expect(before.alarmWakeSources, isNotNull);
      if (ending == 'dispose') {
        h.session.dispose();
      } else if (ending == 'disconnect' || ending == 'same-ID') {
        h.devices.single.drop();
      }
      if (ending == 'B' || ending == 'same-ID') {
        final pending = h.connect(ending == 'B' ? 'B' : 'A');
        expect(h.telemetry.vehicle.handlebarsLocked, isNull);
        expect(h.telemetry.vehicle.alarmStatus, isNull);
        await pending;
      }
      final after = h.telemetry.snapshot.vehicle;
      expect(after.handlebarsLocked, isNull);
      expect(after.alarmStatus, isNull);
      expect(after.alarmLastTrigger, isNull);
      expect(after.alarmWakeSources, isNull);
    });
  }

  test(
      'battery conversions, cache-before-ping/notify, copied session-tagged snapshots',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    for (final name in ['primarySOC', 'secondarySOC', 'cbbSOC', 'auxSOC']) {
      h.effects.trace.clear();
      r[name].number(81);
      expect(h.effects.trace, ['cache:A', 'ping:A', 'notify']);
    }
    r['primaryCycles'].number(190);
    r['secondaryCycles'].number(75);
    r['cbbVoltage'].number(3700999);
    r['cbbCapacity'].number(3000123);
    r['auxVoltage'].number(15000);
    r['cbbCharging'].text('charging');
    r['auxCharging'].text('absorption-charge');
    final s = h.telemetry.snapshot;
    expect(s.scooterId, 'A');
    expect(s.generation, h.sessionEffects.tokens.single.generation);
    expect(s.battery.cbbVoltage, 3700);
    expect(s.battery.cbbCapacity, 3000);
    expect(s.battery.auxVoltage, 15000);
    expect(s.battery.primaryCycles, 190);
    expect(s.battery.secondaryCycles, 75);
    expect(s.battery.cbbCharging, true);
    expect(s.battery.auxCharging, AUXChargingState.absorptionCharge);
    r['primarySOC'].number(22);
    expect(s.battery.primarySOC, 81);
    expect(h.telemetry.snapshot.revision, greaterThan(s.revision));
    r['primarySOC'].values.deliver([1, 2]);
    expect(h.telemetry.battery.primarySOC, 22);
    r['cbbCharging'].text('unknown');
    r['auxCharging'].text('unknown');
    expect(h.telemetry.battery.cbbCharging, true);
    expect(h.telemetry.battery.auxCharging, AUXChargingState.absorptionCharge);
    r['cbbCharging'].text('not-charging');
    r['auxCharging'].text('not-charging');
    expect(h.telemetry.battery.cbbCharging, false);
    expect(h.telemetry.battery.auxCharging, AUXChargingState.none);
  });

  test(
      'vehicle aggregation and optional groups retain defaults and unknown parsing',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    h.effects.trace.clear();
    r['state'].text('parked');
    expect(h.effects.trace, ['notify', 'ping:A', 'aggregate']);
    expect(h.telemetry.state, ScooterState.parked);
    r['powerState'].text('running');
    r['state'].text('stand-by');
    expect(h.effects.transitions.last,
        (ScooterState.parked, ScooterState.standby));
    r['state'].text('garbage');
    r['powerState'].text('garbage');
    expect(h.telemetry.vehicle.vehicleState, ScooterVehicleState.unknown);
    expect(h.telemetry.vehicle.powerState, ScooterPowerState.unknown);
    r['seat'].text('open');
    expect(h.telemetry.vehicle.seatClosed, false);
    r['seat'].text('unknown');
    expect(h.telemetry.vehicle.seatClosed, true);
    h.effects.trace.clear();
    r['handlebar'].text('unlocked');
    expect(h.effects.trace, ['cache:A', 'ping:A', 'notify']);
    r['handlebar'].text('unknown');
    expect(h.telemetry.vehicle.handlebarsLocked, isNull);
    r['umsStatus'].number(9);
    expect(h.telemetry.vehicle.usbMode, isNull);
    r['umsStatus'].number(1);
    r['umsStatus'].number(9);
    expect(h.telemetry.vehicle.usbMode, UsbMode.massStorage);
    r['umsStatus'].number(0);
    expect(h.telemetry.vehicle.usbMode, UsbMode.normal);
    h.effects.trace.clear();
    r['navigationActive'].number(1);
    expect(h.effects.trace, ['navigation:true', 'ping:A', 'notify']);
    r['navigationActive'].number(7);
    expect(h.telemetry.vehicle.navigationActive, false);
    h.effects.trace.clear();
    r['alarmLastTrigger'].text('motion,invalid');
    expect(h.telemetry.vehicle.alarmLastTrigger,
        (source: 'motion', timestamp: null));
    expect(h.effects.trace, ['notify']);
    r['alarmLastTrigger'].text('');
    expect(h.telemetry.vehicle.alarmLastTrigger, isNull);
  });

  test(
      'missing optional groups still wire required values and odometer refresh',
      () async {
    final h = _Harness(optional: false);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    r['primarySOC'].number(56);
    r['state'].text('stand-by');
    expect(h.telemetry.battery.primarySOC, 56);
    expect(h.telemetry.vehicle.powerState, isNull);
    expect(h.telemetry.vehicle.usbMode, isNull);
    expect(h.telemetry.vehicle.alarmStatus, isNull);
    r['odometer'].reads.single.complete([1, 2, 0, 0, 99]);
    await _flush();
    expect(h.telemetry.identity.odometerMeters, 513);
    h.telemetry.refreshOdometer();
    expect(r['odometer'].reads.length, 2);
    await h.connect('B');
    r['odometer'].reads.last.complete([88, 0, 0, 0]);
    await _flush();
    expect(h.telemetry.identity.odometerMeters, isNull);
  });

  test('seed retains non-protection cache and two cached capabilities',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    r['cbbVoltage'].number(3300000);
    r['seat'].text('open');
    r['alarmStatus'].text('armed');
    r['alarmLastTrigger'].text('motion,2026-01-02T03:04:05Z');
    r['alarmWakeSources'].values.deliver([1, 3, 60, 0, 0, 0]);
    h.telemetry.seed(const CachedTelemetry(
        primarySOC: 50,
        secondarySOC: 60,
        cbbSOC: 70,
        auxSOC: 80,
        handlebarsLocked: true,
        isLibrescoot: true,
        supportsHibernateFor: true,
        supportsApnConfig: false));
    expect(h.telemetry.battery.primarySOC, 50);
    expect(h.telemetry.battery.secondarySOC, 60);
    expect(h.telemetry.battery.cbbSOC, 70);
    expect(h.telemetry.battery.auxSOC, 80);
    expect(h.telemetry.battery.cbbVoltage, isNull);
    expect(h.telemetry.vehicle.seatClosed, isNull);
    expect(h.telemetry.vehicle.handlebarsLocked, isNull);
    expect(h.telemetry.vehicle.alarmStatus, isNull);
    expect(h.telemetry.vehicle.alarmLastTrigger, isNull);
    expect(h.telemetry.vehicle.alarmWakeSources, isNull);
    expect(h.telemetry.identity.nrfVersion, isNull);
    expect(h.telemetry.identity.isLibrescoot, true);
    expect(_caps(h.telemetry.identity),
        [true, null, false, null, null, null, null, null]);
  });

  test('navigation capability version enables route plans', () async {
    final h = _Harness(
      capabilityGroups: () async => const LsCapabilityGroups(
        {'nav': 2},
        usedFallback: false,
      ),
    );
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();

    expect(h.telemetry.identity.supportsNavigation, isTrue);
    expect(h.telemetry.identity.navigationCapabilityVersion, 2);
    expect(h.telemetry.identity.supportsRoutePlans, isTrue);
  });

  test(
      'firmware-ready dispatch precedes sequential probes and every capability is cached',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    expect(h.queries, _queryOrder);
    expect(_caps(h.telemetry.identity),
        [true, true, true, true, true, true, false, false]);
    // The identity verdict is dispatchable before anything probes for it, and
    // the UI is notified once the first probe step publishes.
    expect(h.effects.trace.take(2), ['cache:A', 'firmware:A:true']);
    expect(h.effects.trace, contains('notify'));
    expect(h.effects.patches.length, 7);
    expect(h.effects.patches[0].$2.isLibrescoot, true);
    expect(h.effects.patches[1].$2.supportsHibernateFor, true);
    expect(h.effects.patches[2].$2.supportsScheduledHibernation, true);
    expect(h.effects.patches[3].$2.supportsApnConfig, true);
    expect(h.effects.patches[4].$2.supportsBatteryKeepActive, true);
    expect(h.effects.patches[5].$2.supportsAlarmControl, true);
    // Trip and retention follow their own probes, so the patches carry what the
    // probe concluded rather than an assumption about the harness.
    expect(h.effects.patches[5].$2.supportsTripCounter,
        h.telemetry.identity.supportsTripCounter);
    expect(h.effects.patches[6].$2.supportsTripExpunge,
        h.telemetry.identity.supportsTripExpunge);
    expect(h.effects.patches.every((p) => p.$1 == 'A'), true);
  });

  test('a session starts with the capabilities the last probe cached',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.connect('A');
    h.telemetry.seed(const CachedTelemetry(
        supportsAlarmControl: true,
        supportsTripCounter: true,
        supportsTripExpunge: false,
        supportsScheduledHibernation: true,
        supportsBatteryKeepActive: false));
    final identity = h.telemetry.identity;
    expect(identity.supportsAlarmControl, true);
    expect(identity.supportsTripCounter, true);
    expect(identity.supportsTripExpunge, false);
    expect(identity.supportsScheduledHibernation, true);
    expect(identity.supportsBatteryKeepActive, false);
  });

  test('a scooter that reports the trip counter caches that too', () async {
    final h = _Harness(groups: const {'pm', 'config', 'ble', 'alarm', 'trip'});
    addTearDown(h.dispose);
    final r = await h.connect('A');
    // The trip counter is read over the extended channel as soon as the probe
    // reports support for it, so the harness needs that channel wired.
    final extended = _Extended();
    r.extendedCommandCharacteristic = extended;
    r.extendedResponseCharacteristic = extended;
    _firmware(r);
    await _flush();
    expect(h.telemetry.identity.supportsTripCounter, true);
    final cached = h.effects.patches
        .map((p) => p.$2)
        .firstWhere((patch) => patch.supportsTripCounter != null);
    expect(cached.supportsTripCounter, true);
    expect(cached.supportsAlarmControl, true);
  });

  test('a librescoot scooter missing the extended channel is reported',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isTrue);
  });

  test('a complete table on a responsive channel is not reported', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    r.extendedCommandCharacteristic =
        r.chars['extendedCommand'] = _Characteristic();
    r.extendedResponseCharacteristic =
        r.chars['extendedResponse'] = _Characteristic();
    _firmware(r);
    await _flush();
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('a present but silent extended channel is not a stale table', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    r.extendedCommandCharacteristic =
        r.chars['extendedCommand'] = _Characteristic();
    r.extendedResponseCharacteristic =
        r.chars['extendedResponse'] = _Characteristic();
    r.noteSilentExtendedCommand();
    r.noteSilentExtendedCommand();
    _firmware(r);
    await _flush();
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('stock firmware is never reported for its missing extended channel',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r, 'stock');
    await _flush();
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('a refused operation reports the table as out of date', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    r.gattTableMismatch = true;
    _firmware(r, 'stock');
    await _flush();
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isTrue);
  });

  test('stock firmware disables all capabilities without probes', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r, 'stock');
    await _flush();
    expect(h.queries, isEmpty);
    expect(_caps(h.telemetry.identity), List.filled(8, false));
    // The nRF verdict, then the stale capabilities this scooter may have
    // cached from a librescoot session of its own.
    expect(h.effects.patches.first.$2.isLibrescoot, false);
    expect(h.effects.patches.last.$2.supportsAlarmControl, false);
  });

  test('iMX version does not leak between scooter connections', () async {
    final h = _Harness(imxVersion: 'v1.15.0');
    addTearDown(h.dispose);

    final librescoot = await h.connect('A');
    librescoot['state'].text('parked');
    _firmware(librescoot);
    await _flush();
    expect(h.telemetry.identity.imxVersion, 'v1.15.0');
    expect(h.telemetry.identity.isLibrescoot, true);

    final stock = await h.connect('B');
    stock.imxVersionCharacteristic =
        stock.chars['imxVersion'] = _Characteristic(answer: const []);
    stock['state'].text('parked');
    _firmware(stock);
    await _flush();

    expect(h.telemetry.identity.imxVersion, isNull);
    expect(h.telemetry.identity.isLibrescoot, false);
    final verdictPatch = h.effects.patches.lastWhere(
      (patch) => patch.$1 == 'B' && patch.$2.isLibrescoot != null,
    );
    expect(verdictPatch.$2.isLibrescoot, false);
  });

  test('a stock system behind a librescoot nRF clears the capabilities',
      () async {
    // The nRF is a librescoot build, and stays one after a stock image is
    // flashed; stock firmware never answers the version query.
    final h = _Harness(imxVersion: '');
    addTearDown(h.dispose);
    final r = await h.connect('A');
    h.telemetry.identity
      ..supportsAlarmControl = true
      ..supportsApnConfig = true
      ..supportsTripCounter = true;
    _firmware(r);
    await _flush();

    expect(_caps(h.telemetry.identity), List.filled(8, false));
    expect(h.queries, isEmpty,
        reason: 'a stock system is not probed for librescoot services');
    expect(h.telemetry.identity.isLibrescoot, false);
  });

  test('a librescoot system behind the nRF is probed as usual', () async {
    // MDB versions are tags or nightly/build stamps, never suffixed with -ls;
    // only the nRF build carries that suffix.
    final h = _Harness(imxVersion: 'v1.15.0+20240809183558');
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();

    expect(h.queries, _queryOrder);
    expect(h.telemetry.identity.supportsHibernateFor, true);
    expect(h.telemetry.identity.isLibrescoot, true);
  });

  test('a system that answers without a version is stock', () async {
    final h = _Harness(imxVersion: '');
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();

    expect(h.queries, isEmpty);
    expect(h.telemetry.identity.isLibrescoot, false);
  });

  test('a hibernating system keeps the cached capabilities', () async {
    final h = _Harness(imxVersion: '');
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _wireExtended(r);
    h.telemetry.identity
      ..supportsAlarmControl = true
      ..supportsApnConfig = true
      ..supportsTripCounter = true;
    r['powerState'].text('hibernating');
    _firmware(r);
    await _flush();

    expect(h.queries, isEmpty, reason: 'a hibernating MDB cannot answer');
    expect(h.telemetry.identity.supportsAlarmControl, true);
    expect(h.telemetry.identity.supportsApnConfig, true);
    expect(h.telemetry.identity.supportsTripCounter, true);
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('an off system keeps the cached capabilities', () async {
    final h = _Harness(imxVersion: '');
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _wireExtended(r);
    h.telemetry.identity.supportsAlarmControl = true;
    r['state'].text('off');
    _firmware(r);
    await _flush();

    expect(h.queries, isEmpty);
    expect(h.telemetry.identity.supportsAlarmControl, true);
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('a silent capability answer keeps the cached capabilities', () async {
    final h = _Harness(
        capabilityGroups: () async =>
            const LsCapabilityGroups({}, usedFallback: true, answered: false));
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _wireExtended(r);
    h.telemetry.identity
      ..supportsAlarmControl = true
      ..supportsTripCounter = true;
    _firmware(r);
    await _flush();

    expect(h.queries, ['cap:ext']);
    expect(h.telemetry.identity.supportsAlarmControl, true);
    expect(h.telemetry.identity.supportsTripCounter, true);
    expect(h.telemetry.identity.bluetoothTableOutOfDate, isFalse);
  });

  test('an answered empty capability list clears the capabilities', () async {
    final h = _Harness(
        capabilityGroups: () async =>
            const LsCapabilityGroups({}, usedFallback: true),
        setting: (_) async => null);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _wireExtended(r);
    h.telemetry.identity.supportsAlarmControl = true;
    _firmware(r);
    await _flush();

    expect(h.queries, _queryOrder);
    expect(_caps(h.telemetry.identity), List.filled(8, false));
  });

  test('a channel that stops answering clears the cached capabilities',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    // Everything the last nightly session cached, as if the scooter still ran
    // librescoot: the probe must not leave these standing when nothing answers.
    h.telemetry.identity
      ..supportsHibernateFor = true
      ..supportsScheduledHibernation = true
      ..supportsApnConfig = true
      ..supportsAlarmControl = true
      ..supportsTripCounter = true
      ..supportsBatteryKeepActive = true;
    r.noteSilentExtendedCommand();
    r.noteSilentExtendedCommand();

    _firmware(r);
    await _flush();

    expect(_caps(h.telemetry.identity), List.filled(8, false));
    expect(h.queries, isEmpty, reason: 'a dead channel is not probed');
    final patch = h.effects.patches.last.$2;
    expect(patch.supportsAlarmControl, false);
    expect(patch.supportsApnConfig, false);
    expect(patch.supportsTripCounter, false);
  });

  test('queued capability probe cannot write after Service Changed rebuild',
      () async {
    final h = _Harness(defaultQueries: true);
    addTearDown(h.dispose);
    final old = await h.connect('A');
    final channel = _Extended();
    old.extendedCommandCharacteristic = channel;
    old.extendedResponseCharacteristic = channel;

    final gate = Completer<void>();
    final blocker = withExtendedChannel(() => gate.future);
    await _flush();
    _firmware(old);
    await _flush();
    h.devices.single.servicesResets.add(null);
    await _flush();
    expect(h.repositories, hasLength(2));

    gate.complete();
    await blocker;
    await _flush();
    expect(channel.notifyWrites, 0);
    expect(channel.writes, isEmpty);
  });

  test(
      'actual shared default queries fail closed when extended group is absent',
      () async {
    final h = _Harness(defaultQueries: true);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    expect(_caps(h.telemetry.identity), List.filled(8, false));
    expect(h.effects.patches.length, 7);
  });

  test(
      'failed or unsupported probes continue sequentially and replace cached true values with false',
      () async {
    final h = _Harness(
        caps: (_) async => throw StateError('failed'),
        setting: (_) async => null);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    h.telemetry.identity.supportsHibernateFor = true;
    h.telemetry.identity.supportsApnConfig = true;
    _firmware(r);
    await _flush();
    expect(h.queries, _queryOrder);
    expect(_caps(h.telemetry.identity), List.filled(8, false));
    expect(h.effects.patches.map((p) => p.$2.supportsHibernateFor).nonNulls,
        [false]);
    expect(
        h.effects.patches.map((p) => p.$2.supportsApnConfig).nonNulls, [false]);
  });

  for (final position in [0, 1, 2]) {
    test(
        'delayed probe $position cannot publish or continue after A/B supersession',
        () async {
      final gate = Completer<void>();
      var calls = 0;
      Future<void> wait() async {
        if (calls++ == position) {
          await gate.future;
        }
      }

      final h = _Harness(caps: (_) async {
        await wait();
        return {'hibernate-for', 'apn', 'forget', 'enable'};
      }, setting: (_) async {
        await wait();
        return '';
      });
      addTearDown(h.dispose);
      final a = await h.connect('A');
      _firmware(a);
      await _flush();
      expect(calls, position + 1);
      await h.connect('B');
      h.effects.trace.clear();
      final patches = h.effects.patches.length;
      gate.complete();
      await _flush();
      expect(calls, position + 1);
      expect(h.effects.trace, isEmpty);
      expect(h.effects.patches.length, patches);
      expect(_caps(h.telemetry.identity), List.filled(8, null));
    });
  }

  for (final boundary in ['notify', 'cache', 'firmware']) {
    test('reentrant $boundary invalidation cannot continue probing or publish',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final r = await h.connect('A');
      void invalidate() {
        h.telemetry.invalidate();
      }

      if (boundary == 'notify') {
        h.effects.onChanged = () {
          if (h.telemetry.identity.supportsHibernateFor != null) {
            invalidate();
          }
        };
      }
      if (boundary == 'cache') {
        h.effects.onCache = invalidate;
      }
      if (boundary == 'firmware') {
        h.effects.onFirmware = invalidate;
      }
      _firmware(r);
      await _flush();
      expect(h.queries, boundary == 'notify' ? ['cap:ext'] : isEmpty);
      expect(h.telemetry.identity.supportsScheduledHibernation, isNull);
      if (boundary == 'cache') {
        expect(h.effects.trace, ['cache:A']);
      }
      if (boundary == 'firmware') {
        expect(h.effects.trace, ['cache:A', 'firmware:A:true']);
      }
    });
  }

  test(
      'reentrant battery cache replacement suppresses ping/notification after mutation of old session',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    h.effects.onCache = () {
      h.telemetry.invalidate();
      h.telemetry.seed(const CachedTelemetry(primarySOC: 9));
    };
    h.effects.trace.clear();
    r['primarySOC'].number(88);
    expect(h.telemetry.battery.primarySOC, 9);
    expect(h.effects.trace, ['cache:A']);
  });

  test(
      'default runtime executes real capability transport in order with immediate responses',
      () async {
    final h = _Harness(defaultQueries: true);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    final extended = _Extended();
    addTearDown(extended.responses.close);
    r.extendedCommandCharacteristic = extended;
    r.extendedResponseCharacteristic = extended;
    _firmware(r);
    await _flush();
    expect(extended.writes, [
      'cap:ext',
      'get:pm.scheduled-hibernate-enabled',
      'get:scooter.battery-keep-active-on-seatbox-open'
    ]);
    expect(_caps(h.telemetry.identity),
        [true, true, true, true, true, true, false, false]);
    expect(extended.responses.hasListener, false);
  });

  for (final ending in ['same-ID', 'disconnect', 'dispose']) {
    test('delayed capability result is discarded on $ending', () async {
      final gate = Completer<Set<String>>();
      final h = _Harness(caps: (_) => gate.future);
      addTearDown(h.dispose);
      final r = await h.connect('A');
      _firmware(r);
      await _flush();
      if (ending == 'dispose') {
        h.telemetry.dispose();
      } else {
        h.devices.single.drop();
        if (ending == 'same-ID') {
          await h.connect('A');
        }
      }
      h.effects.trace.clear();
      gate.complete({'hibernate-for'});
      await _flush();
      expect(h.queries, ['cap:ext']);
      expect(h.effects.trace, isEmpty);
      expect(h.telemetry.identity.supportsHibernateFor, isNull);
    });
  }

  test('disposed telemetry cannot bind a still-current session again',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    final token = h.sessionEffects.tokens.single;
    h.telemetry.dispose();
    h.telemetry.bind(token, r);
    h.effects.trace.clear();
    r['primarySOC'].number(44);
    expect(h.telemetry.battery.primarySOC, isNull);
    expect(h.effects.trace, isEmpty);
  });

  test('alarm and charging notifications decode all supported wire values',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    r['alarmStatus'].text('armed');
    expect(h.telemetry.vehicle.alarmStatus, AlarmStatus.armed);
    r['alarmStatus'].text('other');
    expect(h.telemetry.vehicle.alarmStatus, AlarmStatus.unknown);
    r['alarmWakeSources'].values.deliver([1, 3, 60, 0, 0, 0]);
    final wake = h.telemetry.vehicle.alarmWakeSources!;
    expect(wake.hibernating, true);
    expect(wake.motionWouldWake, true);
    expect(wake.wakeTimerDuration, const Duration(seconds: 60));
    r['alarmWakeSources'].values.deliver([1]);
    expect(h.telemetry.vehicle.alarmWakeSources, same(wake));
    r['alarmLastTrigger'].text('motion,2026-01-02T03:04:05Z');
    expect(h.telemetry.vehicle.alarmLastTrigger,
        (source: 'motion', timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5)));
    for (final entry in {
      'float-charge': AUXChargingState.floatCharge,
      'bulk-charge': AUXChargingState.bulkCharge
    }.entries) {
      r['auxCharging'].text(entry.key);
      expect(h.telemetry.battery.auxCharging, entry.value);
    }
  });

  test('reentrant aggregate notification stops old ping and cooldown effect',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    h.effects.onChanged = h.telemetry.invalidate;
    h.effects.trace.clear();
    r['state'].text('parked');
    expect(h.effects.trace, ['notify']);
    expect(h.effects.transitions, isEmpty);
  });

  test(
      'refetch only updates saved levels while linking and transport retain original reset phases',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.connect('A');
    final identity = h.telemetry.identity;
    identity.nrfVersion = 'live';
    identity.odometerMeters = 123;
    identity.supportsBondForget = true;
    h.telemetry.vehicle.seatClosed = true;
    h.telemetry.vehicle.handlebarsLocked = true;
    h.telemetry.refetchCache(
        const CachedTelemetry(primarySOC: 8, handlebarsLocked: false));
    expect(h.telemetry.battery.primarySOC, 8);
    expect(h.telemetry.vehicle.handlebarsLocked, true);
    expect(identity.nrfVersion, 'live');
    expect(identity.odometerMeters, 123);
    expect(identity.supportsBondForget, true);
    h.telemetry.refetchCache(null);
    expect(h.telemetry.battery.primarySOC, isNull);
    expect(h.telemetry.vehicle.handlebarsLocked, true);
    h.telemetry.seed(const CachedTelemetry(supportsApnConfig: true));
    expect(identity.nrfVersion, isNull);
    expect(identity.odometerMeters, 123);
    expect(identity.supportsBondForget, isNull);
    expect(h.telemetry.vehicle.seatClosed, isNull);
    expect(h.telemetry.vehicle.handlebarsLocked, isNull);
    h.telemetry.prepare(const CachedTelemetry(supportsApnConfig: true));
    expect(identity.odometerMeters, isNull);
    expect(identity.supportsApnConfig, true);
  });

  for (final capability in ['pm', 'config']) {
    test(
        'reentrant $capability cache patch prevents following publication and probe',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final r = await h.connect('A');
      h.effects.onCache = () {
        final patch = h.effects.patches.last.$2;
        if (capability == 'pm'
            ? patch.supportsHibernateFor != null
            : patch.supportsApnConfig != null) {
          h.telemetry.invalidate();
        }
      };
      _firmware(r);
      await _flush();
      expect(h.queries,
          capability == 'pm' ? ['cap:ext'] : _queryOrder.take(2).toList());
      expect(h.effects.trace.last, 'cache:A');
    });
  }

  test('trip retention writes a complete policy and re-reads it', () async {
    var remote = 'age:365d';
    final h = _Harness(
      setting: (_) async => remote,
      settingWrite: (key, value) async {
        expect(key, 'trip.expunge');
        remote = value;
      },
    );
    addTearDown(h.dispose);
    await h.connect('A');
    h.telemetry.identity.supportsTripExpunge = true;

    expect((await h.telemetry.refreshTripExpunge())!.wireValue, 'age:365d');
    await h.telemetry.setTripExpunge(TripExpunge(TripExpungePolicy.size, '0'));

    expect(h.telemetry.tripExpunge!.wireValue, 'size:0');
    expect(h.queries, [
      'trip.expunge',
      'set:trip.expunge:size:0',
      'trip.expunge',
    ]);
  });

  test(
      'trip retention retains and re-reads the scooter value after a set failure',
      () async {
    var reads = 0;
    final h = _Harness(
      setting: (_) async {
        reads++;
        return 'count:4';
      },
      settingWrite: (_, __) async => throw StateError('rejected'),
    );
    addTearDown(h.dispose);
    await h.connect('A');
    h.telemetry.identity.supportsTripExpunge = true;
    await h.telemetry.refreshTripExpunge();

    await expectLater(
        h.telemetry.setTripExpunge(TripExpunge(TripExpungePolicy.count, '5')),
        throwsStateError);
    expect(h.telemetry.tripExpunge!.wireValue, 'count:4');
    expect(reads, 2);
  });

  test('trip retention is unavailable until its get probe succeeds', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.connect('A');
    h.telemetry.identity.supportsTripExpunge = false;

    expect(await h.telemetry.refreshTripExpunge(), isNull);
    await expectLater(h.telemetry.setTripExpunge(const TripExpunge.never()),
        throwsStateError);
    expect(h.queries, isEmpty);
  });

  test(
      'late failed capability is logged but never cached or published to replacement',
      () async {
    final gate = Completer<Set<String>>();
    final h = _Harness(caps: (_) => gate.future);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    await h.connect('B');
    h.effects.trace.clear();
    gate.completeError(StateError('obsolete'));
    await _flush();
    expect(h.effects.trace, isEmpty);
    expect(h.queries, ['cap:ext']);
    expect(h.telemetry.identity.supportsHibernateFor, isNull);
  });
}
