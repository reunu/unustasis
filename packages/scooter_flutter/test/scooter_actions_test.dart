import 'dart:async';
import 'dart:convert';
// Flutter's test clock dependency; no production dependency added.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:scooter_core/scooter_core.dart';

class Device extends Fake implements BluetoothDevice {
  Device(String id, this.trace) : remoteId = DeviceIdentifier(id);
  final List<String> trace;
  @override
  final DeviceIdentifier remoteId;
  bool live = false;
  final states =
      StreamController<BluetoothConnectionState>.broadcast(sync: true);
  final rssi = <Completer<int>>[];
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
    trace.add('$remoteId:disconnect');
    drop();
  }

  void drop() {
    if (!live) return;
    live = false;
    states.add(BluetoothConnectionState.disconnected);
  }

  @override
  Future<void> removeBond({int timeout = 30}) async {
    trace.add('$remoteId:removeBond');
  }

  @override
  Future<int> readRssi({int timeout = 15}) {
    final gate = Completer<int>();
    rssi.add(gate);
    return gate.future;
  }
}

class Bluetooth extends Fake implements FlutterBluePlusMockable {
  @override
  Future<void> stopScan() async {}
}

class Characteristic extends Fake implements BluetoothCharacteristic {
  Characteristic(this.id, this.trace);
  final String id;
  final List<String> trace;
  final responses =
      StreamController<List<int>>.broadcast(sync: true, onCancel: () {});
  Future<void> Function(String)? onWrite;
  Completer<void>? notifyGate;
  @override
  bool isNotifying = true;
  @override
  Stream<List<int>> get onValueReceived => responses.stream;
  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    await notifyGate?.future;
    isNotifying = notify;
    return true;
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    trace.add('$id:read');
    return [];
  }

  @override
  Future<void> write(List<int> bytes,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) async {
    final command = ascii.decode(bytes);
    trace.add('$id:$command');
    await onWrite?.call(command);
  }

  void reply(String value) => responses.add(ascii.encode(value));
}

class Repository extends CharacteristicRepository {
  // ignore: use_super_parameters
  Repository(Device device, List<String> trace)
      : wire = Characteristic(device.remoteId.str, trace),
        super(device) {
    commandCharacteristic = hibernationCommandCharacteristic = wire;
    extendedCommandCharacteristic = extendedResponseCharacteristic = wire;
    stateCharacteristic = seatCharacteristic = wire;
  }
  final Characteristic wire;
  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {}
  @override
  bool anyAreNull() => false;
}

class TelemetryEffects extends Fake implements ScooterTelemetryEffects {}

class Effects implements ScooterActionEffects {
  Effects(this.trace);
  final List<String> trace;
  final events = <ActionEvent>[];
  final warnings = <HandlebarWarning>[];
  final errors = <Object>[];
  void Function()? onAck, onRssi, onCooldown, onWarning;
  @override
  void acknowledged(ActionEvent event) {
    events.add(event);
    trace.add('ack:${event.kind.name}:${event.source.name}');
    onAck?.call();
  }

  @override
  void handlebarWarning(HandlebarWarning warning) {
    warnings.add(warning);
    trace.add('warning');
    onWarning?.call();
  }

  @override
  void cooldownStarted() {
    trace.add('cooldown');
    onCooldown?.call();
  }

  @override
  void rssiChanged(int value) {
    trace.add('rssi:$value');
    onRssi?.call();
  }

  @override
  void failed(Object error, StackTrace stack) {
    errors.add(error);
  }
}

class SessionEffects implements ScooterSessionEffects {
  late Harness h;
  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {
    h.trace.add('target:$id');
  }

  @override
  void invalidateTelemetry() => h.actions.invalidate();
  @override
  void linking(SessionConnection connection) {}
  @override
  void transportConnected(SessionConnection connection) {}
  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {}
  @override
  void wireTelemetry(
          SessionConnection connection, CharacteristicRepository repository) =>
      h.actions.bind(connection, repository);
  @override
  void readyMetadata(SessionConnection connection) {}
  @override
  void ready(SessionConnection connection) {}
  @override
  void disconnected(String? id) => h.actions.invalidate();
}

class Harness {
  Harness(this.time, {Future<void> Function(Duration)? delay}) {
    effects = Effects(trace);
    final phases = SessionEffects()..h = this;
    session = ScooterSession(
        flutterBluePlus: Bluetooth(),
        effects: phases,
        onChanged: () {},
        findEligibleScooter: () async => null,
        isScanning: () => false,
        onStart: () {},
        isAndroid: false,
        isIOS: false,
        deviceFromId: (id) => devices[id]!,
        repositoryFactory: (d) => repos[d.remoteId.str]!);
    actions = ScooterActions(
        session: session,
        telemetry: telemetry,
        settings: () => settings,
        effects: effects,
        now: () => time.elapsed,
        delay: delay,
        location: () => const ActionLocation(1, 2));
    connect('A');
    trace.clear();
  }
  final FakeAsync time;
  final trace = <String>[];
  final devices = <String, Device>{};
  final repos = <String, Repository>{};
  final telemetry = ScooterTelemetry(effects: TelemetryEffects());
  late final ScooterSession session;
  late final ScooterActions actions;
  late final Effects effects;
  ActionSettings settings = const ActionSettings();
  Device get device => devices[session.device!.remoteId.str]!;
  Characteristic get wire => repos[session.device!.remoteId.str]!.wire;
  void connect(String id) {
    devices[id] = Device(id, trace);
    repos[id] = Repository(devices[id]!, trace);
    session.connectToScooterId(id);
    time.flushMicrotasks();
  }

  void standby() {
    telemetry.state = ScooterState.standby;
    actions.telemetryChanged();
  }

  void dispose() {
    actions.dispose();
    session.dispose();
    telemetry.dispose();
    time.flushMicrotasks();
  }
}

Future<void> settleTransport() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('confirmed open seat writes two ordinary locks sequentially with one set of effects', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true, warnOfUnlockedHandlebars: true);
      h.telemetry.vehicle.handlebarsLocked = false;
      final first = Completer<void>();
      h.wire.onWrite = (_) => first.future;
      var done = false;
      h.actions.lock(confirmOpenSeat: true).then((_) => done = true);
      time.flushMicrotasks();
      expect(h.trace, ['A:$lockCommand']);
      expect(h.effects.events, isEmpty);
      first.complete(); time.flushMicrotasks();
      expect(h.trace.take(3), ['A:$lockCommand', 'A:$lockCommand', 'ack:lock:app']);
      time.elapse(const Duration(seconds: 5));
      expect(done, true);
      expect(h.effects.events, hasLength(1));
      expect(h.effects.warnings, hasLength(1));
      expect(h.trace.where((s) => s == 'cooldown'), hasLength(1));
      expect(h.trace.where((s) => s.contains('blinker both')), hasLength(1));
      h.dispose();
    });
  });
  for (final change in ['first-fails', 'second-fails', 'B', 'same-id', 'disconnect', 'dispose', 'repository']) {
    test('confirmed open seat partial issuance never replays after $change', () {
      fakeAsync((time) {
        final h = Harness(time);
        final wire = h.wire;
        var writes = 0;
        wire.onWrite = (_) async {
          writes++;
          if (change == 'first-fails' || (change == 'second-fails' && writes == 2)) throw StateError('write failed');
          if (writes != 1 || change == 'second-fails') return;
          if (change == 'dispose') {
            h.actions.dispose();
          } else if (change == 'disconnect') {
            h.device.drop();
          } else if (change == 'repository') {
            h.actions.bind(h.session.currentConnection!, Repository(h.device, h.trace));
          } else {
            if (change == 'same-id') h.session.connected = false;
            h.connect(change == 'B' ? 'B' : 'A');
          }
        };
        Object? error;
        h.actions.lock(confirmOpenSeat: true).catchError((Object e) { error = e; });
        time.elapse(const Duration(seconds: 20));
        expect(error, isStateError);
        expect(writes, change == 'second-fails' ? 2 : 1);
        expect(h.trace.where((s) => s.endsWith(lockCommand)), hasLength(writes));
        expect(h.effects.events, isEmpty);
        expect(h.effects.warnings, isEmpty);
        expect(h.trace.where((s) => s.contains('blinker') || s == 'cooldown'), isEmpty);
        h.connect('C'); time.elapse(const Duration(seconds: 20));
        expect(h.trace.where((s) => s.startsWith('C:') && s.contains(lockCommand)), isEmpty);
        h.dispose();
      });
    });
  }
  for (final kind in [EventType.lock, EventType.unlock, EventType.openSeat]) {
    test('explicit $kind rejects partial discovery and stale capture without native issuance', () {
      fakeAsync((time) {
        final h = Harness(time);
        final connection = h.session.currentConnection!;
        final repository = h.repos['A']!;
        repository.commandCharacteristic = null;
        expect(h.actions.canDispatchExplicitAction(connection), isFalse);
        bool? issued;
        h.actions.dispatchExplicitAction(connection, kind).then((value) => issued = value);
        time.flushMicrotasks(); expect(issued, isFalse); expect(h.trace, isEmpty);
        repository.commandCharacteristic = repository.wire;
        expect(h.actions.canDispatchExplicitAction(connection), isTrue);
        h.connect('B'); h.trace.clear();
        expect(h.actions.canDispatchExplicitAction(connection), isFalse);
        h.actions.dispatchExplicitAction(connection, kind).then((value) => issued = value);
        time.flushMicrotasks(); expect(issued, isFalse); expect(h.trace, isEmpty);
        h.dispose();
      });
    });
    test('explicit $kind preserves native ACK effects and propagates post-write effect errors', () {
      fakeAsync((time) {
        final h = Harness(time);
        h.effects.onAck = () => throw StateError('effect after native ACK');
        Object? error;
        h.actions.dispatchExplicitAction(h.session.currentConnection!, kind).catchError((Object e) {
          error = e; return false;
        });
        time.flushMicrotasks();
        expect(error, isA<StateError>());
        expect(h.effects.events.single.kind, kind);
        expect(h.effects.events.single.source, kind == EventType.openSeat ? EventSource.app : EventSource.background);
        expect(h.trace.where((event) => event.startsWith('A:scooter:')), hasLength(1));
        h.dispose();
      });
    });
  }

  test(
      'unlock trace preserves captured SOC/source/settings and unawaited seat ACK',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings =
          const ActionSettings(openSeatOnUnlock: true, hazardLocking: true);
      h.telemetry.battery.primarySOC = 80;
      h.telemetry.battery.secondarySOC = 50;
      final seat = Completer<void>();
      h.wire.onWrite = (c) async {
        if (c == seatCommand) await seat.future;
      };
      var done = false;
      h.actions.unlock(source: EventSource.background).then((_) => done = true);
      time.flushMicrotasks();
      h.settings = const ActionSettings();
      h.telemetry.battery.primarySOC = 1;
      expect(h.trace, ['A:$unlockCommand', 'ack:unlock:background']);
      time.elapse(const Duration(seconds: 1));
      expect(h.trace.last, 'A:$seatCommand');
      time.elapse(const Duration(seconds: 2));
      expect(h.trace.last, 'A:scooter:blinker both');
      time.elapse(const Duration(milliseconds: 1200));
      expect(h.trace.last, 'A:scooter:blinker off');
      time.elapse(const Duration(milliseconds: 3800));
      expect(done, true);
      seat.complete();
      time.flushMicrotasks();
      expect(
          h.effects.events
              .map((e) => (e.kind, e.source, e.primarySOC, e.secondarySOC)),
          [
            (EventType.unlock, EventSource.background, 80, 50),
            (EventType.openSeat, EventSource.auto, 80, 50)
          ]);
      h.dispose();
    });
  });
  for (final kind in ['unlock', 'lock', 'seat', 'wake', 'hibernate']) {
    test('$kind write failure emits no event', () {
      fakeAsync((time) {
        final h = Harness(time);
        h.wire.onWrite = (_) async => throw StateError('write');
        final futures = {
          'unlock': () => h.actions.unlock(),
          'lock': () => h.actions.lock(),
          'seat': () => h.actions.openSeat(),
          'wake': () => h.actions.wakeUp(),
          'hibernate': () => h.actions.hibernate()
        };
        Object? error;
        futures[kind]!().catchError((Object e) {
          error = e;
        });
        time.flushMicrotasks();
        expect(error, isStateError);
        expect(h.effects.events, isEmpty);
        h.dispose();
      });
    });
  }
  test('basic commands are not globally serialized', () {
    fakeAsync((time) {
      final h = Harness(time);
      final gate = Completer<void>();
      h.wire.onWrite = (c) async {
        if (c == unlockCommand) await gate.future;
      };
      h.actions.unlock(checkHandlebars: false);
      h.actions.openSeat();
      time.flushMicrotasks();
      expect(h.trace.take(2), ['A:$unlockCommand', 'A:$seatCommand']);
      gate.complete();
      time.flushMicrotasks();
      h.dispose();
    });
  });
  for (final lock in [true, false]) {
    test('unknown protection permits ${lock ? 'lock' : 'unlock'} without inventing a warning', () {
      fakeAsync((time) {
        final h = Harness(time);
        h.settings = const ActionSettings(warnOfUnlockedHandlebars: true);
        h.telemetry.vehicle.handlebarsLocked = null;
        var done = false;
        (lock ? h.actions.lock() : h.actions.unlock()).then((_) => done = true);
        time.elapse(const Duration(seconds: 7));
        expect(done, true);
        expect(h.trace, contains('A:${lock ? lockCommand : unlockCommand}'));
        expect(h.effects.events, hasLength(1));
        expect(h.effects.warnings, isEmpty);
        expect(h.telemetry.vehicle.handlebarsLocked, isNull);
        h.dispose();
      });
    });
    for (final warn in [true, false]) {
      test(
          '${lock ? 'lock' : 'unlock'} warnings $warn do not fail acknowledged action',
          () {
        fakeAsync((time) {
          final h = Harness(time);
          h.settings = ActionSettings(
              warnOfUnlockedHandlebars: warn, hazardLocking: true);
          h.telemetry.vehicle.handlebarsLocked = !lock;
          var done = false;
          (lock ? h.actions.lock() : h.actions.unlock())
              .then((_) => done = true);
          time.elapse(const Duration(seconds: 7));
          expect(done, true);
          expect(h.effects.warnings.length, lock && !warn ? 0 : 1);
          expect(h.trace, contains('A:scooter:blinker both'));
          if (lock) expect(h.actions.coolingDown, true);
          h.dispose();
        });
      });
    }
  }
  for (final change in ['B', 'same-id', 'disconnect', 'dispose']) {
    test('delayed unlock steps and warnings reject $change', () {
      fakeAsync((time) {
        final h = Harness(time);
        h.settings =
            const ActionSettings(openSeatOnUnlock: true, hazardLocking: true);
        h.telemetry.vehicle.handlebarsLocked = true;
        h.actions.unlock().catchError((Object _) {});
        time.flushMicrotasks();
        if (change == 'dispose') {
          h.actions.dispose();
        } else if (change == 'disconnect') {
          h.device.drop();
        } else {
          if (change == 'same-id') h.session.connected = false;
          h.connect(change == 'B' ? 'B' : 'A');
        }
        time.flushMicrotasks();
        final trace = List.of(h.trace);
        time.elapse(const Duration(seconds: 20));
        expect(h.trace, trace);
        expect(h.effects.warnings, isEmpty);
        h.dispose();
      });
    });
    test('late RSSI rejects $change', () {
      fakeAsync((time) {
        final h = Harness(time);
        h.settings = const ActionSettings(autoUnlock: true, optionalAuth: true);
        h.standby();
        h.actions.startPolling();
        time.elapse(const Duration(seconds: 3));
        final old = h.device;
        if (change == 'dispose') {
          h.actions.dispose();
        } else if (change == 'disconnect') {
          old.drop();
        } else {
          if (change == 'same-id') h.session.connected = false;
          h.connect(change == 'B' ? 'B' : 'A');
        }
        old.rssi.single.complete(-20);
        time.flushMicrotasks();
        expect(h.effects.events, isEmpty);
        expect(h.trace.where((e) => e.startsWith('rssi:')), isEmpty);
        h.dispose();
      });
    });
  }
  test('wake alone never hazards and uses app source without SOC', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.telemetry.battery.primarySOC = 80;
      h.actions.wakeUp();
      time.elapse(const Duration(seconds: 10));
      expect(h.trace, ['A:wakeup', 'ack:wakeUp:app']);
      expect(h.effects.events.single.primarySOC, null);
      h.dispose();
    });
  });
  test(
      'wake subscribes before synchronous standby and shares successful unlock hazards',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.wire.onWrite = (c) async {
        if (c == 'wakeup') h.standby();
      };
      var done = false;
      h.actions
          .wakeUpAndUnlock(source: EventSource.background)
          .then((_) => done = true);
      time.elapse(const Duration(seconds: 7));
      expect(done, true);
      expect(h.trace, [
        'A:wakeup',
        'ack:wakeUp:app',
        'A:$unlockCommand',
        'ack:unlock:background',
        'A:scooter:blinker both',
        'A:scooter:blinker off'
      ]);
      h.dispose();
    });
  });
  test('one 45s budget expires underlying delayed seat and hazard writes', () {
    fakeAsync((time) {
      final delay = Completer<void>();
      final h = Harness(time, delay: (_) => delay.future);
      h.settings =
          const ActionSettings(openSeatOnUnlock: true, hazardLocking: true);
      Object? error;
      h.actions.wakeUpAndUnlock().catchError((Object e) {
        error = e;
      });
      time.elapse(const Duration(seconds: 44));
      h.standby();
      time.flushMicrotasks();
      expect(h.trace, contains('A:$unlockCommand'));
      time.elapse(const Duration(seconds: 1));
      expect(error, isA<TimeoutException>());
      final trace = List.of(h.trace);
      delay.complete();
      time.elapse(const Duration(seconds: 20));
      expect(h.trace, trace);
      expect(h.effects.events.length, 2);
      h.dispose();
    });
  });
  test('hung wake is bounded and cannot unlock after timeout', () {
    fakeAsync((time) {
      final h = Harness(time);
      final gate = Completer<void>();
      h.wire.onWrite = (_) => gate.future;
      Object? error;
      h.actions.wakeUpAndUnlock().catchError((Object e) {
        error = e;
      });
      time.elapse(const Duration(seconds: 45));
      expect(error, isA<TimeoutException>());
      h.standby();
      gate.complete();
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      expect(h.trace, ['A:wakeup']);
      h.dispose();
    });
  });
  test('wake failure and disconnect cancel standby wait deadline', () {
    fakeAsync((time) {
      final h = Harness(time);
      Object? error;
      h.actions.wakeUpAndUnlock().catchError((Object e) {
        error = e;
      });
      time.flushMicrotasks();
      h.device.drop();
      time.flushMicrotasks();
      expect(error, isStateError);
      expect(time.nonPeriodicTimerCount, 0);
      h.dispose();
    });
  });
  test('reentrant acknowledgement prevents all later delayed actions', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings =
          const ActionSettings(openSeatOnUnlock: true, hazardLocking: true);
      h.effects.onAck = h.actions.invalidate;
      h.actions.unlock().catchError((Object _) {});
      time.elapse(const Duration(seconds: 20));
      expect(h.trace, ['A:$unlockCommand', 'ack:unlock:app']);
      h.dispose();
    });
  });
  for (final reentrant in ['rssi', 'cooldown', 'warning']) {
    test('reentrant $reentrant disposal is safe', () {
      fakeAsync((time) {
        final h = Harness(time);
        if (reentrant == 'warning') {
          h.effects.onWarning = h.actions.dispose;
          h.telemetry.vehicle.handlebarsLocked = true;
          h.actions.unlock();
          time.elapse(const Duration(seconds: 5));
          expect(h.effects.warnings.length, 1);
        } else {
          h.settings =
              const ActionSettings(autoUnlock: true, optionalAuth: true);
          h.standby();
          if (reentrant == 'rssi') h.effects.onRssi = h.actions.dispose;
          if (reentrant == 'cooldown') h.effects.onCooldown = h.actions.dispose;
          h.actions.startPolling();
          time.elapse(const Duration(seconds: 3));
          h.device.rssi.single.complete(-20);
          time.flushMicrotasks();
          expect(h.effects.events, isEmpty);
        }
        h.dispose();
      });
    });
  }
  test('keyless threshold auth state enablement cooldown and 60s expiry', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.actions.startPolling();
      h.standby();
      h.settings = const ActionSettings(autoUnlock: true, optionalAuth: false);
      time.elapse(const Duration(seconds: 3));
      h.device.rssi.last.complete(-20);
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      h.settings = const ActionSettings(autoUnlock: true, optionalAuth: true);
      time.elapse(const Duration(seconds: 3));
      h.device.rssi.last.complete(-65);
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      time.elapse(const Duration(seconds: 3));
      h.device.rssi.last.complete(-64);
      time.flushMicrotasks();
      expect(h.effects.events.single.source, EventSource.auto);
      expect(h.actions.coolingDown, true);
      time.elapse(const Duration(seconds: 59));
      expect(h.actions.coolingDown, true);
      time.elapse(const Duration(seconds: 1));
      expect(h.actions.coolingDown, false);
      h.dispose();
    });
  });
  test(
      'pause/resume is idempotent retains remainder and rejects in-flight RSSI',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(autoUnlock: true, optionalAuth: true);
      h.standby();
      h.actions.startPolling();
      h.actions.startPolling();
      time.elapse(const Duration(seconds: 2));
      h.actions.rssiTimer.pause();
      time.elapse(const Duration(seconds: 10));
      expect(h.device.rssi, isEmpty);
      h.actions.rssiTimer.start();
      time.elapse(const Duration(seconds: 1));
      expect(h.device.rssi.length, 1);
      h.actions.rssiTimer.pause();
      h.actions.rssiTimer.start();
      h.device.rssi.single.complete(-20);
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      h.actions.stopPolling();
      final trace = List.of(h.trace);
      time.elapse(const Duration(seconds: 20));
      expect(h.trace, trace);
      h.dispose();
      h.actions.startPolling();
      time.elapse(const Duration(seconds: 20));
      expect(time.periodicTimerCount, 0);
    });
  });
  test(
      'extended settings USB keycard hibernate and clock operations share FIFO',
      () async {
    final time = FakeAsync();
    final h = Harness(time);
    await settleTransport();
    h.trace.clear();
    h.wire.onWrite = (c) async {
      expectSync(h.wire.responses.hasListener, true);
      if (c == 'keycard:list') {
        h.wire.reply('keycard:count:2');
        h.wire.reply('keycard:card:AA');
        h.wire.reply('keycard:card:BB');
      } else {
        h.wire.reply(c.startsWith('set:')
            ? 'set:ok:x'
            : c.startsWith('usb:')
                ? 'usb:ok'
                : c.startsWith('pm:')
                    ? 'pm:ok'
                    : 'time:ok');
      }
    };
    List<String>? cards;
    h.actions.setSetting('x', 'y');
    h.actions.listKeycards().then((c) => cards = c);
    h.actions.enterUMSMode();
    h.actions.hibernateFor(const Duration(seconds: 2));
    h.actions.setClock(DateTime.fromMillisecondsSinceEpoch(1000));
    await settleTransport();
    expect(cards, ['AA', 'BB'], reason: h.trace.toString());
    expect(h.trace.where((s) => s.startsWith('A:')), [
      'A:set:x:y',
      'A:keycard:list',
      'A:usb:ums',
      'A:pm:hibernate-for 2s',
      'A:time:set 1'
    ]);
    expect(h.effects.events.single.kind, EventType.hibernate);
    expect(h.wire.responses.hasListener, false);
    h.dispose();
    await settleTransport();
  });
  test(
      'queued extended operations and delayed notify never write obsolete session',
      () async {
    final time = FakeAsync();
    final h = Harness(time);
    await settleTransport();
    h.trace.clear();
    final old = h.wire;
    final gate = Completer<void>();
    old.isNotifying = false;
    old.notifyGate = gate;
    var failures = 0;
    h.actions.enterUMSMode().catchError((Object _) {
      failures++;
    });
    h.actions.addKeycard('AA').catchError((Object _) {
      failures++;
    });
    await settleTransport();
    h.connect('B');
    gate.complete();
    await settleTransport();
    expect(h.trace.where((s) => s.contains('usb:') || s.contains('keycard:')),
        isEmpty);
    expect(old.responses.hasListener, false);
    expect(failures, 2);
    h.dispose();
    await settleTransport();
  });
  test('bond forget ACK/disconnect precedes phone bond removal', () async {
    final time = FakeAsync();
    final h = Harness(time);
    await settleTransport();
    h.trace.clear();
    h.telemetry.identity.isLibrescoot = true;
    final device = h.device;
    h.wire.onWrite = (_) async {
      h.wire.reply('ble:forget:ok');
    };
    h.actions.forgetCurrentScooter();
    await settleTransport();
    expect(h.trace, ['target:null', 'A:ble:forget']);
    device.drop();
    await settleTransport();
    expect(h.trace,
        ['target:null', 'A:ble:forget', 'A:disconnect', 'A:removeBond']);
    h.dispose();
    await settleTransport();
  });
  test('bond completion after replacement never disconnects or removes B',
      () async {
    final time = FakeAsync();
    final h = Harness(time);
    await settleTransport();
    h.trace.clear();
    h.telemetry.identity.isLibrescoot = true;
    final old = h.wire;
    h.actions.forgetCurrentScooter();
    await settleTransport();
    h.connect('B');
    old.reply('ble:forget:ok');
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(h.trace.where((s) => s == 'B:disconnect' || s == 'B:removeBond'),
        isEmpty);
    h.dispose();
    await settleTransport();
  });
  test(
      'lock event captures location/SOC and delayed hazard does not block result',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.telemetry.battery.primarySOC = 90;
      var done = false;
      h.actions
          .lock(checkHandlebars: false, source: EventSource.auto)
          .then((_) => done = true);
      time.flushMicrotasks();
      expect(done, true);
      final event = h.effects.events.single;
      expect((
        event.source,
        event.primarySOC,
        event.location!.latitude,
        event.location!.longitude
      ), (
        EventSource.auto,
        90,
        1,
        2
      ));
      expect(h.actions.coolingDown, true);
      time.elapse(const Duration(seconds: 1));
      expect(h.trace.last, 'A:scooter:blinker both');
      time.elapse(const Duration(milliseconds: 600));
      expect(h.trace.last, 'A:scooter:blinker off');
      h.dispose();
    });
  });
  test('late basic acknowledgement after same-ID replacement has no event', () {
    fakeAsync((time) {
      final h = Harness(time);
      final gate = Completer<void>();
      h.wire.onWrite = (_) => gate.future;
      h.actions.openSeat().catchError((Object _) {});
      h.session.connected = false;
      h.connect('A');
      gate.complete();
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      h.dispose();
    });
  });
  test('fake seat command acknowledges only after write and defaults to app',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      final gate = Completer<void>();
      h.wire.onWrite = (_) => gate.future;
      h.actions.openSeat();
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      gate.complete();
      time.flushMicrotasks();
      expect(h.trace, ['A:$seatCommand', 'ack:openSeat:app']);
      h.dispose();
    });
  });
  test('wake successful but unlock failed never starts hazards', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.wire.onWrite = (command) async {
        if (command == wakeCommand) h.standby();
        if (command == unlockCommand) throw StateError('unlock refused');
      };
      Object? error;
      h.actions.wakeUpAndUnlock().catchError((Object e) {
        error = e;
      });
      time.elapse(const Duration(seconds: 50));
      expect(error, isStateError);
      expect(h.effects.events.single.kind, EventType.wakeUp);
      expect(h.trace.where((s) => s.contains('blinker')), isEmpty);
      expect(time.nonPeriodicTimerCount, 0);
      h.dispose();
    });
  });
  test('wake missing standby times out and removes its timer', () {
    fakeAsync((time) {
      final h = Harness(time);
      Object? error;
      h.actions.wakeUpAndUnlock().catchError((Object e) {
        error = e;
      });
      time.elapse(const Duration(seconds: 45));
      expect(error, isA<TimeoutException>());
      expect(time.nonPeriodicTimerCount, 0);
      h.standby();
      time.flushMicrotasks();
      expect(h.trace, ['A:wakeup', 'ack:wakeUp:app']);
      h.dispose();
    });
  });
  test('expired normal underlying hazard delay never starts writes', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.actions.wakeUpAndUnlock().catchError((Object _) {});
      time.elapse(const Duration(seconds: 44));
      h.standby();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 20));
      expect(h.trace,
          ['A:wakeup', 'ack:wakeUp:app', 'A:$unlockCommand', 'ack:unlock:app']);
      h.dispose();
    });
  });
  test('delayed lock hazard never acts on replacement', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(hazardLocking: true);
      h.actions.lock(checkHandlebars: false);
      time.flushMicrotasks();
      h.connect('B');
      time.elapse(const Duration(seconds: 2));
      expect(h.trace.where((s) => s.contains('blinker')), isEmpty);
      h.dispose();
    });
  });
  test('keyless read failure does not reuse an older strong RSSI', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(autoUnlock: true, optionalAuth: true);
      h.actions.startPolling();
      time.elapse(const Duration(seconds: 3));
      h.device.rssi.last.complete(-20);
      time.flushMicrotasks(); // Not standby yet.
      h.standby();
      time.elapse(const Duration(seconds: 3));
      h.device.rssi.last.completeError(StateError('disconnected'));
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      h.dispose();
    });
  });
  test(
      'aggregate transition cooldown and overlapping expiry preserve legacy timing',
      () {
    fakeAsync((time) {
      final h = Harness(time);
      h.actions.aggregateTransition(ScooterState.parked, ScooterState.standby);
      expect(h.actions.coolingDown, true);
      time.elapse(const Duration(seconds: 30));
      h.actions.autoUnlockCooldown();
      time.elapse(const Duration(seconds: 30));
      expect(h.actions.coolingDown, false);
      h.dispose();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });
  test('extended negative ACK emits no hibernate event and queue recovers',
      () async {
    final h = Harness(FakeAsync());
    await settleTransport();
    h.trace.clear();
    h.wire.onWrite = (_) async => h.wire.reply('pm:error');
    await expectLater(h.actions.hibernateFor(const Duration(seconds: 2)),
        throwsA('Failed to hibernate, response: pm:error'));
    expect(h.effects.events, isEmpty);
    expect(h.wire.responses.hasListener, false);
    h.wire.onWrite = (_) async => h.wire.reply('usb:ok');
    await h.actions.enterNormalUsbMode();
    expect(h.trace.last, 'A:usb:normal');
    h.dispose();
  });
  test(
      'immediate firmware disconnect after forget ACK is observed without waiting 5s',
      () async {
    final h = Harness(FakeAsync());
    await settleTransport();
    h.trace.clear();
    h.telemetry.identity.isLibrescoot = true;
    final device = h.device;
    h.wire.onWrite = (_) async {
      h.wire.reply('ble:forget:ok');
      device.drop();
    };
    await h.actions.forgetCurrentScooter().timeout(const Duration(seconds: 1));
    expect(h.trace,
        ['target:null', 'A:ble:forget', 'A:disconnect', 'A:removeBond']);
    expect(device.states.hasListener,
        true); // Only the session subscription remains.
    h.dispose();
    await settleTransport();
    expect(device.states.hasListener, false);
  });
  test('RSSI result after its 15s budget cannot unlock the same session', () {
    fakeAsync((time) {
      final h = Harness(time);
      h.settings = const ActionSettings(autoUnlock: true, optionalAuth: true);
      h.standby();
      h.actions.startPolling();
      time.elapse(const Duration(seconds: 3));
      final first = h.device.rssi.first;
      time.elapse(const Duration(seconds: 15));
      first.complete(-20);
      time.flushMicrotasks();
      expect(h.effects.events, isEmpty);
      expect(h.trace.where((s) => s.startsWith('rssi:')), isEmpty);
      h.dispose();
    });
  });
  for (final change in ['B', 'same-id', 'disconnect', 'dispose']) {
    for (final step in [1, 2]) {
      test('scheduled enable stops after step $step on $change', () async {
        final h = Harness(FakeAsync());
        await settleTransport();
        h.trace.clear();
        final wire = h.wire;
        var writes = 0;
        wire.onWrite = (command) async {
          wire.reply('set:ok:${command.split(':')[1]}');
          if (++writes == step) {
            if (change == 'dispose') {
              h.actions.dispose();
            } else if (change == 'disconnect') {
              h.device.drop();
            } else {
              if (change == 'same-id') h.session.connected = false;
              h.connect(change == 'B' ? 'B' : 'A');
            }
          }
        };
        await expectLater(
            h.actions.setScheduledHibernationEnabled(true,
                cron: '0 1 * * *', wakeAfter: const Duration(hours: 2)),
            throwsStateError);
        await settleTransport();
        expect(h.trace.where((e) => e.contains(':set:')), [
          'A:set:pm.scheduled-hibernate-cron:0 1 * * *',
          if (step == 2) 'A:set:pm.scheduled-hibernate-duration:7200s',
        ]);
        expect(wire.responses.hasListener, false);
        h.dispose();
        await settleTransport();
      });
    }
  }
  for (final mode in ['first-enable', 'existing-enable', 'disable']) {
    test('scheduled $mode preserves defaults and enabled-last order', () async {
      final h = Harness(FakeAsync());
      await settleTransport();
      h.trace.clear();
      h.wire.onWrite =
          (command) async => h.wire.reply('set:ok:${command.split(':')[1]}');
      await h.actions.setScheduledHibernationEnabled(mode != 'disable',
          cron: mode == 'existing-enable' ? null : '0 1 * * *',
          wakeAfter:
              mode == 'existing-enable' ? null : const Duration(hours: 2));
      expect(h.trace, [
        if (mode == 'first-enable') ...[
          'A:set:pm.scheduled-hibernate-cron:0 1 * * *',
          'A:set:pm.scheduled-hibernate-duration:7200s',
        ],
        'A:set:pm.scheduled-hibernate-enabled:${mode != 'disable'}',
      ]);
      h.dispose();
      await settleTransport();
    });
  }
  test('scheduled command failure leaves acknowledged prefix without enabling',
      () async {
    final h = Harness(FakeAsync());
    await settleTransport();
    h.trace.clear();
    h.wire.onWrite = (command) async => h.wire.reply(
        command.contains('duration')
            ? 'set:error'
            : 'set:ok:${command.split(':')[1]}');
    await expectLater(
        h.actions.setScheduledHibernationEnabled(true,
            cron: '0 1 * * *', wakeAfter: const Duration(hours: 2)),
        throwsA(
            'Failed to set pm.scheduled-hibernate-duration, response: set:error'));
    expect(h.trace, [
      'A:set:pm.scheduled-hibernate-cron:0 1 * * *',
      'A:set:pm.scheduled-hibernate-duration:7200s'
    ]);
    expect(h.effects.events, isEmpty);
    expect(h.wire.responses.hasListener, false);
    h.dispose();
    await settleTransport();
  });
}
