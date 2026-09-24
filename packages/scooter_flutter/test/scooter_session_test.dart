import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

// Only the owner's retry deadline uses virtual time. BLE futures/streams retain
// real microtask ordering, including independently controlled cancellation.
class _Clock {
  Duration now = Duration.zero;
  final waits = <({Duration due, Completer<void> gate})>[];
  Future<void> delay(Duration duration) {
    final gate = Completer<void>();
    waits.add((due: now + duration, gate: gate));
    return gate.future;
  }

  Future<void> pump([Duration duration = Duration.zero]) async {
    now += duration;
    final due = waits.where((wait) => wait.due <= now).toList();
    for (final wait in due) {
      waits.remove(wait);
      wait.gate.complete();
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _Bluetooth extends Fake implements FlutterBluePlusMockable {
  final scans = StreamController<bool>.broadcast();
  final List<String> trace;
  _Bluetooth(this.trace);
  int scanReads = 0;
  bool scanning = false;
  @override
  bool get isScanningNow => scanning;
  @override
  Stream<bool> get isScanning {
    scanReads++;
    return scans.stream;
  }

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      Stream.value(BluetoothAdapterState.on);
  @override
  Future<void> stopScan() async => trace.add('stopScan');
}

class _Link {
  bool connected = false;
  int disconnects = 0;
}

class _CancelGatedStream extends StreamView<void> {
  _CancelGatedStream(super.stream, this.gate);
  final Future<void> gate;
  @override
  StreamSubscription<void> listen(void Function(void)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _CancelGatedSubscription(super.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError), gate);
}

class _CancelGatedSubscription implements StreamSubscription<void> {
  _CancelGatedSubscription(this.delegate, this.gate);
  final StreamSubscription<void> delegate;
  final Future<void> gate;
  @override
  Future<void> cancel() async {
    await delegate.cancel();
    await gate;
  }
  @override
  void onData(void Function(void)? handleData) => delegate.onData(handleData);
  @override
  void onError(Function? handleError) => delegate.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => delegate.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => delegate.pause(resumeSignal);
  @override
  void resume() => delegate.resume();
  @override
  bool get isPaused => delegate.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => delegate.asFuture(futureValue);
}

class _Device extends Fake implements BluetoothDevice {
  _Device(String id, this.trace, [_Link? link])
      : remoteId = DeviceIdentifier(id),
        link = link ?? _Link() {
    servicesResets = StreamController<void>.broadcast(sync: true);
  }
  final List<String> trace;
  final _Link link;
  final connections = <Completer<void>>[];
  final states = StreamController<BluetoothConnectionState>.broadcast();
  late final StreamController<void> servicesResets;
  Completer<void>? servicesResetCancelGate;
  Completer<BluetoothBondState>? bondStateGate;
  Completer<void>? bondGate;
  Completer<void>? priorityGate;
  Completer<void>? disconnectGate;
  Object? priorityError;
  Object? disconnectError;
  BluetoothBondState bonding = BluetoothBondState.bonded;
  @override
  final DeviceIdentifier remoteId;
  @override
  bool get isConnected => link.connected;
  @override
  bool get isDisconnected => !link.connected;
  @override
  DisconnectReason? get disconnectReason => null;
  @override
  Stream<BluetoothConnectionState> get connectionState {
    trace.add('$remoteId.listen');
    return states.stream;
  }

  @override
  Stream<void> get onServicesReset {
    trace.add('$remoteId.servicesReset');
    final gate = servicesResetCancelGate;
    return gate == null
        ? servicesResets.stream
        : _CancelGatedStream(servicesResets.stream, gate.future);
  }

  @override
  Stream<BluetoothBondState> get bondState {
    trace.add('$remoteId.bondState');
    return bondStateGate?.future.asStream() ?? Stream.value(bonding);
  }

  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 35),
      int? mtu = 512,
      bool autoConnect = false}) async {
    expect(timeout, const Duration(seconds: 30));
    trace.add('$remoteId.connect');
    final gate = Completer<void>();
    connections.add(gate);
    await gate.future;
    link.connected = true;
  }

  @override
  Future<void> createBond({int timeout = 90, Uint8List? pin}) async {
    expect(timeout, 30);
    trace.add('$remoteId.createBond');
    await bondGate?.future;
  }

  @override
  Future<void> requestConnectionPriority(
      {required ConnectionPriority connectionPriorityRequest}) async {
    expect(connectionPriorityRequest, ConnectionPriority.high);
    trace.add('$remoteId.priority');
    await priorityGate?.future;
    if (priorityError != null) throw priorityError!;
  }

  @override
  Future<void> disconnect(
      {int timeout = 35, bool queue = true, int androidDelay = 2000}) async {
    trace.add('$remoteId.disconnect');
    link.disconnects++;
    await disconnectGate?.future;
    if (disconnectError != null) throw disconnectError!;
    link.connected = false;
  }

  void drop() {
    link.connected = false;
    states.add(BluetoothConnectionState.disconnected);
  }
}

class _Repository extends CharacteristicRepository {
  _Repository(super.scooter, this.trace);
  final List<String> trace;
  Completer<void>? gate;
  bool missing = false;
  String? invalidTable;
  Completer<void>? validationGate;
  void Function()? afterValidationHandoff;
  int discoveries = 0;
  int pairingChecks = 0;
  Completer<void>? pairingGate;
  Object? pairingError;
  @override
  Future<void> findAll({bool additionalLibrescootFeatures = false}) async {
    expect(additionalLibrescootFeatures, isTrue);
    discoveries++;
    trace.add('${scooter.remoteId}.discover');
    await gate?.future;
  }

  @override
  Future<void> confirmPairing(
      {bool Function()? isCurrent,
      Duration timeout = const Duration(seconds: 60)}) async {
    pairingChecks++;
    trace.add('${scooter.remoteId}.pair');
    await pairingGate?.future;
    if (pairingError != null) throw pairingError!;
  }

  @override
  bool anyAreNull() {
    trace.add('${scooter.remoteId}.complete');
    return missing;
  }

  @override
  Future<String?> validateGattTable({required bool isAndroid}) async {
    trace.add('${scooter.remoteId}.validate');
    await validationGate?.future;
    final result =
        missing ? 'mandatory characteristics are missing' : invalidTable;
    final afterHandoff = afterValidationHandoff;
    if (afterHandoff != null) {
      afterValidationHandoff = null;
      scheduleMicrotask(() => scheduleMicrotask(afterHandoff));
    }
    return result;
  }
}

class _Effects implements ScooterSessionEffects {
  _Effects(this.trace);
  final List<String> trace;
  final connections = <SessionConnection>[];
  final repositories = <CharacteristicRepository>[];
  void Function(String)? onPhase;
  void Function(SessionConnection)? onLinking;
  Completer<void>? widgetGate;
  void phase(String event) {
    trace.add(event);
    onPhase?.call(event);
  }

  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) =>
      phase('manual:$id:$includeMetadata');
  @override
  void invalidateTelemetry() => phase('invalidate');
  @override
  void linking(SessionConnection connection) {
    phase('${connection.id}.linking');
    onLinking?.call(connection);
  }

  @override
  void transportConnected(SessionConnection connection) {
    connections.add(connection);
    phase('${connection.id}.published');
  }

  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {
    phase('${connection.id}.widgetGroup');
    await widgetGate?.future;
    if (connection.isCurrent) phase('${connection.id}.widget');
  }

  @override
  void wireTelemetry(
      SessionConnection connection, CharacteristicRepository repository) {
    repositories.add(repository);
    phase('${connection.id}.wire');
  }

  @override
  void readyMetadata(SessionConnection connection) =>
      phase('${connection.id}.metadata');
  @override
  void ready(SessionConnection connection) => phase('${connection.id}.ready');
  @override
  void disconnected(String? id) => phase('disconnected:$id');
}

class _Harness {
  _Harness(_Clock clock, {bool android = false, bool ios = false}) {
    bluetooth = _Bluetooth(trace);
    effects = _Effects(trace);
    devices = {'A': makeDevice('A'), 'B': makeDevice('B')};
    session = ScooterSession(
      flutterBluePlus: bluetooth,
      effects: effects,
      onChanged: () {
        trace.add(
            'connected:${session.connected}:${session.connectingScooterId}');
        onChanged?.call();
      },
      deviceFromId: (id) => devices[id]!,
      repositoryFactory: (device) {
        final calls = repositoryFactoryCalls.update(device, (value) => value + 1,
            ifAbsent: () => 1);
        final queued = queuedRepositories[device];
        if (queued != null && queued.isNotEmpty) {
          final repository = queued.removeAt(0);
          repositories[device] = repository;
          repositoryHistory.add(repository);
          return repository;
        }
        final prepared = repositories[device];
        if (calls == 1 && prepared != null) {
          repositoryHistory.add(prepared);
          return prepared;
        }
        final repository = _Repository(device, trace)
          ..invalidTable = defaultRepositoryInvalid;
        repositories[device] = repository;
        repositoryHistory.add(repository);
        return repository;
      },
      clearGattCache: (device) async {
        trace.add('${device.remoteId}.refresh');
        if (refreshError case final error?) throw error;
        return refreshResult;
      },
      findEligibleScooter: () {
        session.stopAutoRestart();
        trace.add('scan');
        return candidate?.future ?? Future.value(devices['A']);
      },
      isScanning: () => bluetooth.scanning,
      onStart: () => trace.add('splash'),
      delay: clock.delay,
      isAndroid: android,
      isIOS: ios,
    );
  }
  final trace = <String>[];
  final allDevices = <_Device>[];
  final repositories = <BluetoothDevice, _Repository>{};
  final repositoryFactoryCalls = <BluetoothDevice, int>{};
  final queuedRepositories = <BluetoothDevice, List<_Repository>>{};
  final repositoryHistory = <_Repository>[];
  final attempts = <Future<Object?>>[];
  bool? refreshResult;
  Object? refreshError;
  String? defaultRepositoryInvalid;
  late final Map<String, _Device> devices;
  late final _Bluetooth bluetooth;
  late final _Effects effects;
  late final ScooterSession session;
  Completer<BluetoothDevice?>? candidate;
  void Function()? onChanged;
  _Device makeDevice(String id, [_Link? link]) {
    final device = _Device(id, trace, link);
    allDevices.add(device);
    return device;
  }

  Future<Object?> connect(String id, {bool automatic = false, int? intent}) {
    final result = session
        .connectToScooterId(id,
            automatic: automatic, expectedIntentGeneration: intent)
        .then<Object?>((_) => null, onError: (Object e, StackTrace _) => e);
    attempts.add(result);
    return result;
  }

  Future<void> finish(_Clock tester, String id) async {
    devices[id]!.connections.last.complete();
    await tester.pump();
    expect(session.connected, isTrue);
    expect(session.device, same(devices[id]));
  }

  Future<void> close() async {
    effects.onPhase = null;
    effects.onLinking = null;
    onChanged = null;
    session.dispose();
    for (final device in allDevices) {
      for (final gate in device.connections) {
        if (!gate.isCompleted) gate.completeError(StateError('teardown'));
      }
      if (device.bondStateGate case final gate? when !gate.isCompleted) {
        gate.complete(BluetoothBondState.bonded);
      }
      for (final gate in [
        device.servicesResetCancelGate,
        device.bondGate,
        device.priorityGate,
        device.disconnectGate
      ]) {
        if (gate != null && !gate.isCompleted) gate.complete();
      }
    }
    for (final repository in repositoryHistory) {
      if (repository.gate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      if (repository.validationGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
      if (repository.pairingGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
    }
    if (effects.widgetGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    if (candidate case final gate? when !gate.isCompleted) gate.complete(null);
    await Future.wait(attempts);
    for (final device in allDevices) {
      expect(device.states.hasListener, isFalse);
      expect(device.servicesResets.hasListener, isFalse);
      await device.states.close();
      await device.servicesResets.close();
    }
    expect(bluetooth.scans.hasListener, isFalse);
    await bluetooth.scans.close();
  }
}

void main() {
  final harnesses = <_Harness>[];
  late _Clock clock;
  void sessionTest(String name, Future<void> Function(_Clock) body) {
    test(name, () async {
      clock = _Clock();
      try {
        await body(clock);
      } finally {
        await Future.wait(harnesses.map((h) => h.close()));
        await clock.pump(const Duration(seconds: 3));
        harnesses.clear();
      }
    });
  }

  _Harness create({bool android = false, bool ios = false}) {
    final h = _Harness(clock, android: android, ios: ios);
    harnesses.add(h);
    return h;
  }

  sessionTest('construction is inert; disposal rejects future requests',
      (tester) async {
    final h = create();
    expect(h.trace, isEmpty);
    expect(h.bluetooth.scanReads, 0);
    h.session.dispose();
    h.trace.clear();
    await h.connect('A');
    h.session.start();
    h.session.startAutoRestart();
    await tester.pump(const Duration(seconds: 10));
    expect(h.trace, isEmpty);
  });

  for (final bonded in [false, true]) {
    sessionTest(
        'Android ${bonded ? 'bond reuse' : 'bond creation'} precedes priority/discovery',
        (tester) async {
      final h = create(android: true);
      final a = h.devices['A']!;
      a.bonding = bonded ? BluetoothBondState.bonded : BluetoothBondState.none;
      if (!bonded) a.bondGate = Completer<void>();
      final result = h.connect('A');
      await tester.pump();
      a.connections.single.complete();
      await tester.pump();
      if (!bonded) {
        expect(h.trace.last, 'A.createBond');
        expect(h.session.device, isNull);
        a.bondGate!.complete();
        await tester.pump();
      }
      expect(await result, isNull);
      expect(h.trace, [
        'manual:A:true',
        'invalidate',
        'connected:false:A',
        'A.linking',
        'A.servicesReset',
        'stopScan',
        'A.connect',
        'A.bondState',
        if (!bonded) 'A.createBond',
        'A.priority',
        'A.published',
        'A.discover',
        'A.validate',
        'A.wire',
        'A.metadata',
        'connected:true:null',
        'A.ready',
        'A.listen',
      ]);
    });
  }

  sessionTest('iOS confirms pairing before the session is published as ready',
      (tester) async {
    final h = create(ios: true);
    final a = h.devices['A']!;
    final repository = _Repository(a, h.trace)
      ..pairingGate = Completer<void>();
    h.repositories[a] = repository;
    final result = h.connect('A');
    await tester.pump();
    a.connections.single.complete();
    await tester.pump();

    expect(repository.pairingChecks, 1);
    expect(h.session.connected, isFalse);
    final pairIndex = h.trace.indexOf('A.pair');
    expect(pairIndex, greaterThan(h.trace.indexOf('A.validate')));
    expect(h.trace.indexOf('A.wire'), -1);

    repository.pairingGate!.complete();
    await tester.pump();

    expect(await result, isNull);
    expect(h.session.connected, isTrue);
    expect(h.trace.indexOf('A.wire'), greaterThan(pairIndex));
    expect(h.trace,
        containsAllInOrder(['A.pair', 'A.wire', 'A.metadata', 'A.ready']));
  });

  sessionTest(
      'iOS pairing failure fails the connect instead of reporting ready',
      (tester) async {
    final h = create(ios: true);
    final a = h.devices['A']!;
    h.repositories[a] = _Repository(a, h.trace)
      ..pairingError = StateError('pairing was dismissed');
    final result = h.connect('A');
    await tester.pump();
    a.connections.single.complete();
    await tester.pump();

    expect(await result, isA<StateError>());
    expect(h.session.connected, isFalse);
    expect(h.trace, isNot(contains('A.wire')));
  });

  sessionTest(
      'priority failure is non-fatal and missing characteristics recover before ready',
      (tester) async {
    final h = create(android: true);
    final a = h.devices['A']!;
    a.priorityError = StateError('priority');
    h.repositories[a] = _Repository(a, h.trace)..missing = true;
    final result = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await result, isNull);
    expect(h.trace,
        containsAllInOrder(['A.priority', 'A.discover', 'A.wire', 'A.ready']));
  });

  for (final stage in ['bondState', 'createBond', 'priority']) {
    sessionTest('superseded Android $stage cannot publish or discover',
        (tester) async {
      final h = create(android: true);
      final a = h.devices['A']!;
      if (stage == 'bondState') {
        a.bondStateGate = Completer<BluetoothBondState>();
      }
      if (stage == 'createBond') {
        a.bonding = BluetoothBondState.none;
        a.bondGate = Completer<void>();
      }
      if (stage == 'priority') a.priorityGate = Completer<void>();
      final old = h.connect('A');
      await tester.pump();
      a.connections.single.complete();
      await tester.pump();
      expect(h.trace.last, 'A.$stage');
      final newer = h.connect('B');
      await tester.pump();
      await h.finish(tester, 'B');
      a.bondStateGate?.complete(BluetoothBondState.bonded);
      a.bondGate?.complete();
      a.priorityGate?.complete();
      await tester.pump();
      expect(await old, isNull);
      expect(await newer, isNull);
      expect(h.trace, isNot(contains('A.published')));
      expect(h.session.device, same(h.devices['B']));
      expect(h.devices['B']!.link.disconnects, 0);
    });
  }

  sessionTest('Service Changed during connect is observed before discovery',
      (tester) async {
    final h = create(android: true);
    final result = h.connect('A');
    await tester.pump();
    expect(h.trace, containsAllInOrder(['A.servicesReset', 'A.connect']));
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();
    expect(h.trace.last, 'invalidate');
    await h.finish(tester, 'A');
    expect(await result, isNull);
    expect(h.trace,
        containsAllInOrder(['invalidate', 'A.discover', 'A.validate', 'A.wire']));
  });

  sessionTest(
      'Android validates before wiring and rebuilds after a false refresh result',
      (tester) async {
    final h = create(android: true)..refreshResult = false;
    final first = _Repository(h.devices['A']!, h.trace)
      ..invalidTable = 'collided 48-byte CCCD';
    h.repositories[h.devices['A']!] = first;
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await result, isNull);
    expect(h.repositoryHistory, hasLength(2));
    expect(h.effects.repositories, hasLength(1));
    expect(h.effects.repositories.single, isNot(same(first)));
    expect(h.trace, containsAllInOrder([
      'A.servicesReset',
      'A.discover',
      'A.validate',
      'A.refresh',
      'A.discover',
      'A.validate',
      'A.wire',
    ]));
  });

  sessionTest('iOS retries one transient incomplete table without cache refresh',
      (tester) async {
    final h = create(ios: true);
    final first = _Repository(h.devices['A']!, h.trace)
      ..invalidTable = 'mandatory characteristics are missing';
    h.repositories[h.devices['A']!] = first;
    final result = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await result, isNull);
    expect(h.repositoryHistory, hasLength(2));
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(2));
    expect(h.trace, isNot(contains('A.refresh')));
    expect(h.effects.repositories.single, isNot(same(first)));
  });

  sessionTest('iOS transient-table rediscovery remains bounded', (tester) async {
    final h = create(ios: true)
      ..defaultRepositoryInvalid = 'mandatory characteristics are missing';
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await result, isA<Exception>());
    expect(h.repositoryHistory, hasLength(2));
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(2));
    expect(h.trace, isNot(contains('A.refresh')));
    expect(h.trace, isNot(contains('A.wire')));
  });

  sessionTest('a successful refresh invocation still requires validation',
      (tester) async {
    final h = create(android: true)
      ..refreshResult = true
      ..defaultRepositoryInvalid = 'still collided';
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await result, isA<Exception>());
    expect(h.trace.where((event) => event == 'A.refresh'), hasLength(1));
    expect(h.trace, isNot(contains('A.wire')));
  });

  sessionTest('Android refresh failure exhausts recovery and fails closed',
      (tester) async {
    final h = create(android: true)
      ..refreshError = StateError('refresh unavailable')
      ..defaultRepositoryInvalid = 'collided table';
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await result, isA<Exception>());
    expect(h.trace.where((event) => event == 'A.refresh'), hasLength(1));
    expect(h.trace, isNot(contains('A.wire')));
    expect(h.trace, isNot(contains('A.ready')));
    expect(h.devices['A']!.link.disconnects, 1);
    expect(h.session.connected, isFalse);
  });

  sessionTest(
      'supersession while failed setup cancels observation protects newer link',
      (tester) async {
    final h = create(android: true)..defaultRepositoryInvalid = 'unsafe';
    final oldDevice = h.devices['A']!;
    oldDevice.servicesResetCancelGate = Completer<void>();
    final old = h.connect('A');
    await tester.pump();
    oldDevice.connections.single.complete();
    await tester.pump();
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(2));

    h.defaultRepositoryInvalid = null;
    h.devices['A'] = h.makeDevice('A', oldDevice.link);
    final newer = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    oldDevice.servicesResetCancelGate!.complete();
    await tester.pump();
    expect(await old, isA<Exception>());
    expect(await newer, isNull);
    expect(h.session.connected, isTrue);
    expect(oldDevice.link.disconnects, 0, reason: h.trace.toString());
  });

  sessionTest(
      'Service Changed during initial validation handoff discards the candidate',
      (tester) async {
    final h = create(android: true);
    final first = _Repository(h.devices['A']!, h.trace)
      ..afterValidationHandoff = () => h.devices['A']!.servicesResets.add(null);
    h.repositories[h.devices['A']!] = first;
    final result = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await result, isNull);
    expect(h.repositoryHistory, hasLength(2));
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(2));
    expect(h.effects.repositories, hasLength(1), reason: h.trace.toString());
    expect(h.effects.repositories.single, isNot(same(first)),
        reason: 'the handoff candidate must never start telemetry work');
  });

  sessionTest('Service Changed during discovery discards the obsolete table',
      (tester) async {
    final h = create(android: true);
    final first = _Repository(h.devices['A']!, h.trace)
      ..gate = Completer<void>();
    h.repositories[h.devices['A']!] = first;
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(h.trace.last, 'A.discover');
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();
    expect(h.trace.last, 'invalidate');
    first.gate!.complete();
    await tester.pump();
    expect(await result, isNull);
    expect(h.repositoryHistory, hasLength(2));
    expect(h.effects.repositories, hasLength(1));
    expect(h.effects.repositories.single, isNot(same(first)));
  });

  sessionTest(
      'Service Changed during active recovery handoff discards the candidate',
      (tester) async {
    final h = create(android: true);
    final connected = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await connected, isNull);

    final stale = _Repository(h.devices['A']!, h.trace)
      ..afterValidationHandoff = () => h.devices['A']!.servicesResets.add(null);
    final latest = _Repository(h.devices['A']!, h.trace);
    h.queuedRepositories[h.devices['A']!] = [stale, latest];
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();

    expect(h.repositoryHistory, hasLength(3));
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(3));
    expect(h.effects.repositories, hasLength(2), reason: h.trace.toString());
    expect(h.effects.repositories, isNot(contains(same(stale))),
        reason: 'the handoff candidate must never start telemetry work');
    expect(h.effects.repositories.last, same(latest));
  });

  sessionTest('three invalid active handoffs fail closed without a fourth',
      (tester) async {
    final h = create(android: true);
    final connected = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await connected, isNull);

    final stale = List.generate(3, (_) {
      return _Repository(h.devices['A']!, h.trace)
        ..afterValidationHandoff = () => h.devices['A']!.servicesResets.add(null);
    });
    h.queuedRepositories[h.devices['A']!] = stale.toList();
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();
    await tester.pump();

    expect(h.repositoryHistory, hasLength(4),
        reason: 'the initial table plus exactly three recovery candidates');
    expect(h.trace.where((event) => event == 'A.discover'), hasLength(4));
    expect(h.trace.where((event) => event == 'A.validate'), hasLength(4));
    expect(h.effects.repositories, hasLength(1));
    for (final repository in stale) {
      expect(h.effects.repositories, isNot(contains(same(repository))),
          reason: 'invalidated candidates must not start notify/write work');
    }
    expect(h.devices['A']!.link.disconnects, 1);
    expect(h.devices['A']!.link.connected, isFalse);
    expect(h.session.connected, isFalse);
    expect(h.session.device, isNull);
  });

  for (final platform in ['Android', 'iOS']) {
    sessionTest('$platform Service Changed while active quiesces then rewires',
        (tester) async {
      final h = create(android: platform == 'Android', ios: platform == 'iOS');
      final result = h.connect('A');
      await tester.pump();
      await h.finish(tester, 'A');
      expect(await result, isNull);
      h.trace.clear();
      h.devices['A']!.servicesResets.add(null);
      await tester.pump();
      expect(h.trace.first, 'invalidate');
      expect(h.trace, containsAllInOrder(
          ['invalidate', 'A.discover', 'A.validate', 'A.wire']));
      expect(h.effects.repositories, hasLength(2));
      expect(h.effects.repositories.last,
          isNot(same(h.effects.repositories.first)));
    });
  }

  sessionTest(
      'supersession while active recovery cancels observation protects newer link',
      (tester) async {
    final h = create(android: true);
    final connected = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await connected, isNull);
    final a = h.devices['A']!;
    a.servicesResetCancelGate = Completer<void>();
    h.defaultRepositoryInvalid = 'unsafe';
    a.servicesResets.add(null);
    await tester.pump();
    expect(h.trace.where((event) => event == 'A.validate').length,
        greaterThanOrEqualTo(3));

    h.defaultRepositoryInvalid = null;
    final newer = h.connect('B');
    await tester.pump();
    await h.finish(tester, 'B');
    a.servicesResetCancelGate!.complete();
    await tester.pump();
    expect(await newer, isNull);
    expect(h.session.connected, isTrue);
    expect(h.session.device, same(h.devices['B']));
    expect(h.devices['B']!.link.disconnects, 0);
  });

  sessionTest('repeated Service Changed events coalesce serialized discovery',
      (tester) async {
    final h = create(android: true);
    final result = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    expect(await result, isNull);

    final recovery = _Repository(h.devices['A']!, h.trace)
      ..gate = Completer<void>();
    h.queuedRepositories[h.devices['A']!] = [recovery];
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();
    expect(h.repositoryHistory, hasLength(2));
    h.devices['A']!.servicesResets.add(null);
    await tester.pump();
    expect(h.repositoryHistory, hasLength(2),
        reason: 'a second discovery must not overlap the first');
    recovery.gate!.complete();
    await tester.pump();
    expect(h.repositoryHistory, hasLength(3));
    expect(h.effects.repositories, hasLength(2));
  });

  sessionTest('disconnect during validation cannot wire the repository',
      (tester) async {
    final h = create(android: true);
    final first = _Repository(h.devices['A']!, h.trace)
      ..validationGate = Completer<void>();
    h.repositories[h.devices['A']!] = first;
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(h.trace.last, 'A.validate');
    h.devices['A']!.drop();
    first.validationGate!.complete();
    await tester.pump();
    expect(await result, isA<StateError>());
    expect(h.trace, isNot(contains('A.wire')));
  });

  sessionTest('supersession during validation cannot wire the old repository',
      (tester) async {
    final h = create(android: true);
    final first = _Repository(h.devices['A']!, h.trace)
      ..validationGate = Completer<void>();
    h.repositories[h.devices['A']!] = first;
    final old = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(h.trace.last, 'A.validate');
    final newer = h.connect('B');
    await tester.pump();
    await h.finish(tester, 'B');
    first.validationGate!.complete();
    await tester.pump();
    expect(await old, isNull);
    expect(await newer, isNull);
    expect(h.trace, isNot(contains('A.wire')));
  });

  sessionTest('iOS group and widget precede discovery with captured ID',
      (tester) async {
    final h = create(ios: true);
    h.effects.widgetGate = Completer<void>();
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(h.trace.last, 'A.widgetGroup');
    expect(h.session.connected, isFalse);
    h.effects.widgetGate!.complete();
    await tester.pump();
    expect(await result, isNull);
    expect(
        h.trace,
        containsAllInOrder([
          'A.published',
          'A.widgetGroup',
          'A.widget',
          'A.discover',
          'A.ready'
        ]));
  });

  sessionTest('iOS late hook after disposal does not publish widget/discovery',
      (tester) async {
    final h = create(ios: true);
    h.effects.widgetGate = Completer<void>();
    final result = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    h.session.dispose();
    h.effects.widgetGate!.complete();
    await tester.pump();
    expect(await result, isNull);
    expect(h.trace, isNot(contains('A.widget')));
    expect(h.repositories, isEmpty);
    expect(h.devices['A']!.isConnected, isFalse);
  });

  for (final reuse in [false, true]) {
    for (final success in [false, true]) {
      sessionTest(
          'same-ID ${reuse ? 'same' : 'distinct'} wrapper late ${success ? 'success' : 'failure'} protects newer owner',
          (tester) async {
        final h = create();
        final a = h.devices['A']!;
        final old = h.connect('A');
        await tester.pump();
        h.devices['A'] = reuse ? a : h.makeDevice('A', a.link);
        final newer = h.connect('A');
        await tester.pump();
        await h.finish(tester, 'A');
        expect(await newer, isNull);
        final token = h.session.currentConnection!;
        final failure = StateError('late');
        if (success) {
          a.connections.first.complete();
        } else {
          a.connections.first.completeError(failure);
        }
        await tester.pump();
        expect(await old, success ? isNull : same(failure));
        expect(token.isCurrent, isTrue);
        expect(a.link.disconnects, 0);
        expect(h.effects.repositories, hasLength(1));
      });
    }
  }

  sessionTest(
      'three calls reusing wrapper preserve newest token through both stale completions',
      (tester) async {
    final h = create();
    final first = h.connect('A');
    await tester.pump();
    final second = h.connect('A');
    await tester.pump();
    final third = h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    final a = h.devices['A']!;
    a.connections[0].complete();
    a.connections[1].completeError(StateError('second'));
    await tester.pump();
    expect(await first, isNull);
    expect(await second, isA<StateError>());
    expect(await third, isNull);
    expect(h.session.currentConnection!.isCurrent, isTrue);
    expect(a.link.disconnects, 0);
  });

  sessionTest('late different-ID success disconnects only its own transport',
      (tester) async {
    final h = create();
    final old = h.connect('A');
    await tester.pump();
    h.connect('B');
    await tester.pump();
    await h.finish(tester, 'B');
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await old, isNull);
    expect(h.devices['A']!.link.disconnects, 1);
    expect(h.devices['B']!.link.disconnects, 0);
    expect(h.session.currentConnection!.isCurrent, isTrue);
  });

  sessionTest(
      'discovery failure remains observable; cleanup failure cannot mask stale error',
      (tester) async {
    final h = create();
    final a = h.devices['A']!;
    final gate = Completer<void>();
    h.repositories[a] = _Repository(a, h.trace)..gate = gate;
    final old = h.connect('A');
    await tester.pump();
    a.connections.single.complete();
    await tester.pump();
    a.disconnectError = StateError('cleanup');
    // Replacement is held in its disconnect independently of discovery.
    a.disconnectGate = Completer<void>();
    h.connect('B');
    await tester.pump();
    final failure = StateError('discovery');
    gate.completeError(failure);
    a.disconnectGate!.complete();
    await tester.pump();
    expect(await old, same(failure));
    expect(h.trace, isNot(contains('A.ready')));
  });

  sessionTest(
      'disposal releases published link before replacement constructs device',
      (tester) async {
    final h = create();
    final a = h.devices['A']!;
    final gate = Completer<void>();
    h.repositories[a] = _Repository(a, h.trace)..gate = gate;
    h.connect('A');
    await tester.pump();
    a.connections.single.complete();
    await tester.pump();
    h.connect('B');
    h.session.dispose();
    gate.complete();
    await tester.pump();
    expect(a.link.disconnects, 1);
    expect(h.devices['B']!.connections, isEmpty);
    expect(h.session.device, isNull);
  });

  sessionTest('late connect after disposal is disconnected without effects',
      (tester) async {
    final h = create();
    final old = h.connect('A');
    await tester.pump();
    h.session.dispose();
    h.trace.clear();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(await old, isNull);
    expect(h.trace, ['A.disconnect']);
  });

  for (final phase in ['A.linking', 'A.published', 'A.metadata', 'A.ready']) {
    sessionTest(
        'synchronous $phase reentrancy cannot continue old publications',
        (tester) async {
      final h = create();
      h.effects.onPhase = (event) {
        if (event == phase) h.connect('B');
      };
      final old = h.connect('A');
      await tester.pump();
      if (h.devices['A']!.connections.isNotEmpty) {
        h.devices['A']!.connections.single.complete();
        await tester.pump();
      }
      await h.finish(tester, 'B');
      expect(await old, isNull);
      expect(h.trace, isNot(contains('A.listen')));
      expect(h.session.device, same(h.devices['B']));
    });
  }

  sessionTest(
      'connected notification disposal does not invoke later ready effects',
      (tester) async {
    final h = create();
    h.onChanged = () {
      if (h.session.connected) h.session.dispose();
    };
    h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    expect(h.trace, isNot(contains('A.ready')));
    expect(h.devices['A']!.isConnected, isFalse);
  });

  for (final fromNotification in [false, true]) {
    sessionTest(
        'same-ID manual intent from ${fromNotification ? 'connected notification' : 'ready effect'} retains publishing owner',
        (tester) async {
      final h = create();
      if (fromNotification) {
        h.onChanged = () {
          if (h.session.connected) h.connect('A');
        };
      } else {
        h.effects.onPhase = (event) {
          if (event == 'A.ready') h.connect('A');
        };
      }
      final first = h.connect('A');
      await tester.pump();
      h.devices['A']!.connections.single.complete();
      await tester.pump();
      expect(await first, isNull);
      expect(h.devices['A']!.connections, hasLength(1));
      expect(h.devices['A']!.link.disconnects, 0);
      expect(h.session.currentConnection!.isCurrent, isTrue);
      expect(h.devices['A']!.states.hasListener, isTrue);
      expect(h.trace.where((event) => event == 'manual:A:true'), hasLength(2));
    });
  }

  sessionTest(
      'same-ID adoption cannot revive an owner after reentrant newer intent',
      (tester) async {
    final h = create();
    var published = false;
    h.effects.onPhase = (event) {
      if (event == 'A.ready') {
        published = true;
        h.connect('A');
      } else if (event == 'manual:A:true' && published) {
        h.connect('B');
      }
    };
    final first = h.connect('A');
    await tester.pump();
    h.devices['A']!.connections.single.complete();
    await tester.pump();
    await h.finish(tester, 'B');
    expect(await first, isNull);
    expect(h.devices['A']!.states.hasListener, isFalse);
    expect(h.effects.connections.first.isCurrent, isFalse);
    expect(h.session.currentConnection!.id, 'B');
    expect(h.devices['B']!.link.disconnects, 0);
  });

  sessionTest(
      'same-ID reconnect linking freshness is false until its transport exists',
      (tester) async {
    final h = create();
    final device = h.devices['A']!;
    h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    final previous = h.session.currentConnection!;
    device.drop();
    await tester.pump();
    expect(h.session.connected, isFalse);
    expect(h.session.device, same(device));
    expect(previous.isCurrent, isFalse);

    final linkingFreshness = <bool>[];
    late SessionConnection linking;
    h.effects.onLinking = (connection) {
      linking = connection;
      expect(connection.isCurrentAttempt, isTrue);
      expect(device.connections, hasLength(1));
      linkingFreshness.add(connection.isCurrent);
    };
    Object? reconnectError;
    final reconnect = h.connect('A').then((error) {
      reconnectError = error;
      return error;
    });
    await tester.pump();
    expect(reconnectError, isNull);
    expect(linkingFreshness, [false]);
    expect(device.connections, hasLength(2));
    expect(linking.isCurrent, isFalse);
    await h.finish(tester, 'A');
    expect(await reconnect, isNull);
    expect(h.session.currentConnection, same(linking));
    expect(linking.isCurrent, isTrue);
    expect(previous.isCurrent, isFalse);
    h.session.dispose();
    expect(linking.isCurrent, isFalse);
  });

  sessionTest(
      'freshness expires on replacement and live disconnect, not connect finally',
      (tester) async {
    final h = create();
    h.connect('A');
    await tester.pump();
    await h.finish(tester, 'A');
    final a = h.session.currentConnection!;
    h.connect('B');
    expect(a.isCurrent, isFalse);
    await tester.pump();
    await h.finish(tester, 'B');
    final b = h.session.currentConnection!;
    expect(b.isCurrent, isTrue);
    expect(h.devices['A']!.states.hasListener, isFalse);
    h.devices['A']!.drop();
    await tester.pump();
    expect(h.session.connected, isTrue);
    h.devices['B']!.drop();
    await tester.pump();
    expect(b.isCurrent, isFalse);
    expect(h.session.connected, isFalse);
    expect(h.trace.last, 'disconnected:B');
  });

  sessionTest(
      'manual intent supersedes pending startup candidate and stale automatic request',
      (tester) async {
    final h = create();
    h.candidate = Completer<BluetoothDevice?>();
    h.session.start();
    await tester.pump();
    h.connect('B');
    await tester.pump();
    h.candidate!.complete(h.devices['A']);
    await h.connect('A', automatic: true, intent: 0);
    await tester.pump();
    expect(h.devices['A']!.connections, isEmpty);
    expect(h.session.manualTargetId, 'B');
    h.session.start();
    expect(h.trace.where((event) => event == 'scan'), hasLength(1));
  });

  sessionTest(
      'pinned retry has one three-second loop and re-arms manual intent',
      (tester) async {
    final h = create();
    h.session.startAutoRestart(targetScooterId: 'B');
    h.session.startAutoRestart(targetScooterId: 'B');
    await tester.pump();
    expect(h.bluetooth.scanReads, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(h.devices['B']!.connections, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(h.devices['B']!.connections, hasLength(1));
    h.devices['B']!.connections.first.completeError(StateError('retry'));
    await tester.pump();
    h.bluetooth.scans.add(false);
    h.bluetooth.scans.add(false);
    await tester.pump(const Duration(seconds: 3));
    expect(h.devices['B']!.connections, hasLength(2));
    await h.finish(tester, 'B');
    expect(h.trace.where((event) => event == 'manual:B:false'), hasLength(2));
    expect(h.trace, isNot(contains('scan')));
    h.devices['B']!.drop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(h.devices['B']!.connections, hasLength(3));
    await h.finish(tester, 'B');
    h.session.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  sessionTest(
      'stopping/restarting while listener cancellation yields leaves one listener',
      (tester) async {
    final h = create();
    h.session.foundScooter = true;
    h.session.startAutoRestart();
    h.session.stopAutoRestart();
    h.session.startAutoRestart();
    await tester.pump();
    expect(h.bluetooth.scanReads, 1);
    h.session.dispose();
    expect(h.bluetooth.scans.hasListener, isFalse);
  });

  sessionTest('stop/dispose while retry sleeps prevents any later connect',
      (tester) async {
    final h = create();
    h.session.startAutoRestart(targetScooterId: 'A');
    await tester.pump();
    h.session.stopAutoRestart();
    h.session.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(h.devices['A']!.connections, isEmpty);
    expect(h.session.manualTargetId, isNull);
  });
}
