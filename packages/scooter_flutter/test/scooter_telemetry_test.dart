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
  final values = LateStream();
  final reads = <Completer<List<int>>>[];
  @override
  Stream<List<int>> get lastValueStream => values;
  @override
  Future<bool> setNotifyValue(bool notify,
          {int timeout = 15, bool forceIndications = false}) async =>
      true;
  @override
  Future<List<int>> read({int timeout = 15}) {
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
  @override
  bool get isNotifying => true;
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
    if (command.startsWith('cap:')) {
      final feature = {
        'cap:pm': 'hibernate-for <duration>',
        'cap:config': 'apn',
        'cap:ble': 'forget',
        'cap:alarm': 'enable'
      }[command]!;
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
  @override
  bool get isConnected => live;
  @override
  bool get isDisconnected => !live;
  @override
  DisconnectReason? get disconnectReason => null;
  @override
  Stream<BluetoothConnectionState> get connectionState => states.stream;
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
  _Repository(super.scooter, {bool optional = true}) {
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
      Future<Set<String>> Function(String)? caps,
      Future<String?> Function(String)? setting}) {
    telemetry = ScooterTelemetry(
        effects: effects,
        capabilities: defaultQueries
            ? null
            : (_, __, category) async {
                queries.add(category);
                return caps == null
                    ? {'hibernate-for', 'apn', 'forget', 'enable'}
                    : await caps(category);
              },
        setting: defaultQueries
            ? null
            : (_, __, key) async {
                queries.add(key);
                return setting == null ? '' : await setting(key);
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
          final repo = _Repository(device, optional: optional);
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
    }
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
void _firmware(_Repository repo, [String version = '1.2-ls']) =>
    repo['nrfVersion'].reads.single.complete(utf8.encode(version));
List<bool?> _caps(FirmwareIdentity identity) => [
      identity.supportsHibernateFor,
      identity.supportsScheduledHibernation,
      identity.supportsApnConfig,
      identity.supportsBondForget,
      identity.supportsBatteryKeepActive,
      identity.supportsAlarmControl
    ];
const _queryOrder = [
  'pm',
  'pm.scheduled-hibernate-enabled',
  'config',
  'ble',
  'scooter.battery-keep-active-on-seatbox-open',
  'alarm'
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
    expect(h.telemetry.vehicle.handlebarsLocked, true);
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

  test('seed retains only cached telemetry and two cached capabilities',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    r['cbbVoltage'].number(3300000);
    r['seat'].text('open');
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
    expect(h.telemetry.vehicle.handlebarsLocked, true);
    expect(h.telemetry.identity.nrfVersion, isNull);
    expect(h.telemetry.identity.isLibrescoot, true);
    expect(_caps(h.telemetry.identity), [true, null, false, null, null, null]);
  });

  test(
      'firmware-ready dispatch precedes sequential probes and only two capability patches persist',
      () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    expect(h.queries, _queryOrder);
    expect(_caps(h.telemetry.identity), List.filled(6, true));
    expect(h.effects.trace.take(3), ['cache:A', 'firmware:A:true', 'notify']);
    expect(h.effects.patches.length, 3);
    expect(h.effects.patches[0].$2.isLibrescoot, true);
    expect(h.effects.patches[1].$2.supportsHibernateFor, true);
    expect(h.effects.patches[2].$2.supportsApnConfig, true);
    expect(h.effects.patches.every((p) => p.$1 == 'A'), true);
  });

  test('stock firmware disables all capabilities without probes', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r, 'stock');
    await _flush();
    expect(h.queries, isEmpty);
    expect(_caps(h.telemetry.identity), List.filled(6, false));
    expect(h.effects.patches.single.$2.isLibrescoot, false);
  });

  test(
      'actual shared default queries fail closed when extended group is absent',
      () async {
    final h = _Harness(defaultQueries: true);
    addTearDown(h.dispose);
    final r = await h.connect('A');
    _firmware(r);
    await _flush();
    expect(_caps(h.telemetry.identity), List.filled(6, false));
    expect(h.effects.patches.length, 3);
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
    expect(_caps(h.telemetry.identity), List.filled(6, false));
    expect(h.effects.patches[1].$2.supportsHibernateFor, false);
    expect(h.effects.patches[2].$2.supportsApnConfig, false);
  });

  for (final position in [0, 1, 2, 3, 4, 5]) {
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
      expect(_caps(h.telemetry.identity), List.filled(6, null));
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
      expect(h.queries, boundary == 'notify' ? ['pm'] : isEmpty);
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
      'cap:pm',
      'get:pm.scheduled-hibernate-enabled',
      'cap:config',
      'cap:ble',
      'get:scooter.battery-keep-active-on-seatbox-open',
      'cap:alarm'
    ]);
    expect(_caps(h.telemetry.identity), List.filled(6, true));
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
      expect(h.queries, ['pm']);
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
    expect(h.telemetry.vehicle.handlebarsLocked, false);
    expect(identity.nrfVersion, 'live');
    expect(identity.odometerMeters, 123);
    expect(identity.supportsBondForget, true);
    h.telemetry.refetchCache(null);
    expect(h.telemetry.battery.primarySOC, isNull);
    expect(h.telemetry.vehicle.handlebarsLocked, false);
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
          capability == 'pm' ? ['pm'] : _queryOrder.take(3).toList());
      expect(h.effects.trace.last, 'cache:A');
    });
  }

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
    expect(h.effects.trace, ['failed:pm capability probe failed']);
    expect(h.queries, ['pm']);
    expect(h.telemetry.identity.supportsHibernateFor, isNull);
  });
}
