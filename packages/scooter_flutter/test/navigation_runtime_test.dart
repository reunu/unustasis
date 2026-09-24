import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/extended_response.dart';
// Same coordinate type as the core DTO.
// ignore: depend_on_referenced_packages
import 'package:latlong2/latlong.dart';
import 'package:scooter_flutter/firmware_queries.dart' as queries;

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

class ActionEffects extends Fake implements ScooterActionEffects {}

class SessionEffects implements ScooterSessionEffects {
  late Harness h;
  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {}
  @override
  void invalidateTelemetry() {
    h.navigation.invalidate();
    h.actions.invalidate();
  }

  @override
  void linking(SessionConnection connection) {}
  @override
  void transportConnected(SessionConnection connection) {}
  @override
  Future<void> prepareIosWidget(SessionConnection connection) async {}
  @override
  void wireTelemetry(
      SessionConnection connection, CharacteristicRepository repository) {
    h.navigation.bind(connection, repository);
    h.actions.bind(connection, repository);
  }

  @override
  void readyMetadata(SessionConnection connection) {}
  @override
  void ready(SessionConnection connection) {}
  @override
  void disconnected(String? id) {
    h.navigation.invalidate();
    h.actions.invalidate();
  }
}

class Harness {
  Harness() {
    navigation = NavigationRuntime(
        loadPending: () async {
          await loadGate?.future;
          return stored;
        },
        savePending: (json) async {
          saves.add(json);
          await saveHook?.call(json);
          stored = json;
        },
        changed: () {
          publications++;
          onChanged?.call();
        },
        failed: (error, stack) => errors.add(error));
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
        settings: () => const ActionSettings(),
        effects: ActionEffects());
  }
  final trace = <String>[];
  final devices = <String, Device>{};
  final repos = <String, Repository>{};
  final telemetry = ScooterTelemetry(effects: TelemetryEffects());
  late final ScooterSession session;
  late final ScooterActions actions;
  late final NavigationRuntime navigation;
  String? stored;
  final saves = <String?>[];
  final errors = <Object>[];
  int publications = 0;
  void Function()? onChanged;
  Completer<void>? loadGate;
  Future<void> Function(String?)? saveHook;
  Device get device => devices[session.device!.remoteId.str]!;
  Characteristic get wire => repos[session.device!.remoteId.str]!.wire;
  Future<void> connect([String id = 'A']) async {
    devices[id] = Device(id, trace);
    final repo = repos[id] = Repository(devices[id]!, trace);
    repo.wire.onWrite = (command) async => repo.wire.reply('nav:ok');
    await session.connectToScooterId(id);
  }

  void dispose() {
    navigation.dispose();
    actions.dispose();
    session.dispose();
    telemetry.dispose();
  }
}

NavigationDestination destination([String name = 'First', String id = '1']) =>
    NavigationDestination(location: const LatLng(1, 2), name: name, id: id);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late Harness h;
  setUp(() {
    h = Harness();
  });
  tearDown(() {
    h.dispose();
  });

  test('pending persistence restore and invalid-entry removal retain schema',
      () async {
    final d = destination()..type = SpecialDestinationType.work;
    await h.navigation.setPending(d);
    expect(h.stored, jsonEncode(d.toJson()));
    d.name = 'mutated';
    expect(h.navigation.pending!.name, 'First');
    h.navigation.pending!.name = 'also mutated';
    expect(h.navigation.pending!.name, 'First');
    final expected = h.stored;
    h.stored = '{invalid';
    await h.navigation.restorePending();
    expect(h.saves.last, isNull);
    for (final json in [
      '[]',
      '{"latitude":1,"longitude":2,"type":"invalid"}'
    ]) {
      h.stored = json;
      await h.navigation.restorePending();
      expect(h.stored, isNull);
    }
    h.stored = expected;
    await h.navigation.restorePending();
    expect(h.navigation.pending!.type, SpecialDestinationType.work);
    expect(h.navigation.pending!.name, 'First');
  });
  test(
      'new request during restoration wins without removing persisted replacement',
      () async {
    h.stored = 'invalid';
    h.loadGate = Completer<void>();
    final restoration = h.navigation.restorePending();
    await h.navigation.setPending(destination('New'));
    h.loadGate!.complete();
    await restoration;
    expect(h.navigation.pending!.name, 'New');
    expect(h.saves, hasLength(1));
  });
  test('pending writes/removal serialize and preserve latest request',
      () async {
    final gate = Completer<void>();
    h.saveHook = (_) => gate.future;
    final first = h.navigation.setPending(destination());
    final clear = h.navigation.setPending(null);
    final newer = h.navigation.setPending(destination('New'));
    await flush();
    expect(h.saves, hasLength(1));
    expect(h.navigation.pending!.name, 'New');
    gate.complete();
    await Future.wait([first, clear, newer]);
    expect(h.saves.map((v) => v == null ? null : jsonDecode(v)['name']),
        ['First', null, 'New']);
    expect(jsonDecode(h.stored!)['name'], 'New');
    expect(h.publications, 1);
  });
  test('persistence failure does not poison later pending cancel', () async {
    h.saveHook = (_) async => throw StateError('storage failed');
    await expectLater(h.navigation.setPending(destination()), throwsStateError);
    h.saveHook = null;
    await h.navigation.setPending(null);
    expect(h.stored, isNull);
    expect(h.navigation.pending, isNull);
  });
  test('firmware-ready dispatch only accepts current librescoot identity',
      () async {
    await h.connect();
    await h.navigation.setPending(destination());
    final old = h.session.currentConnection!;
    h.navigation
        .firmwareIdentified(old, const FirmwareSnapshot(isLibrescoot: false));
    await flush();
    expect(h.trace.where((v) => v.contains('nav:')), isEmpty);
    await h.connect('B');
    h.navigation
        .firmwareIdentified(old, const FirmwareSnapshot(isLibrescoot: true));
    await flush();
    expect(h.trace.where((v) => v.contains('nav:')), isEmpty);
    h.navigation.firmwareIdentified(h.session.currentConnection!,
        const FirmwareSnapshot(isLibrescoot: true));
    await flush();
    expect(h.navigation.active!.name, 'First');
    expect(h.navigation.pending, isNull);
    expect(h.stored, isNull);
    expect(
        h.trace.where((v) => v.contains('nav:')), ['B:nav:dest 1.0,2.0,First']);
  });
  for (final transition in [
    'new request',
    'same object',
    'cancel pending',
    'B',
    'same-ID',
    'disconnect',
    'dispose'
  ]) {
    test('pending dispatch rejects $transition while old write is held',
        () async {
      await h.connect();
      final d = destination();
      await h.navigation.setPending(d);
      final oldWire = h.wire;
      final held = Completer<void>();
      oldWire.onWrite = (_) async {
        await held.future;
        oldWire.reply('nav:ok');
      };
      final dispatch = h.navigation.dispatchPending();
      await flush();
      switch (transition) {
        case 'new request':
          await h.navigation.setPending(destination('New'));
        case 'same object':
          d.name = 'New';
          await h.navigation.setPending(d);
        case 'cancel pending':
          await h.navigation.setPending(null);
        case 'B':
          await h.connect('B');
        case 'same-ID':
          h.device.drop();
          await flush();
          await h.connect('A');
        case 'disconnect':
          h.device.drop();
          await flush();
        case 'dispose':
          h.navigation.dispose();
      }
      held.complete();
      await dispatch;
      expect(h.navigation.active, isNull);
      expect(
          h.navigation.pending?.name,
          switch (transition) {
            'new request' || 'same object' => 'New',
            'cancel pending' => null,
            _ => 'First'
          });
      expect(
          jsonDecode(h.stored ?? 'null')?['name'], h.navigation.pending?.name);
    });
  }
  test(
      'firmware-ready duplicate dispatch is coalesced but retry after failure works',
      () async {
    await h.connect();
    await h.navigation.setPending(destination());
    final gate = Completer<void>();
    h.wire.onWrite = (_) async {
      await gate.future;
      h.wire.reply('nav:error');
    };
    final dispatch = h.navigation.dispatchPending();
    await h.navigation.dispatchPending();
    gate.complete();
    await dispatch;
    expect(h.errors, hasLength(1));
    expect(h.navigation.pending, isNotNull);
    expect(h.navigation.active, isNull);
    h.wire.onWrite = (_) async => h.wire.reply('nav:ok');
    await h.navigation.dispatchPending();
    expect(h.trace.where((v) => v.contains('nav:dest')), hasLength(2));
    expect(h.navigation.pending, isNull);
  });
  test('reentrant active publication cannot clear newer pending request',
      () async {
    await h.connect();
    await h.navigation.setPending(destination());
    Future<void>? newRequest;
    h.onChanged = () {
      if (h.navigation.active != null && newRequest == null) {
        newRequest = h.navigation.setPending(destination('New'));
      }
    };
    await h.navigation.dispatchPending();
    await newRequest;
    expect(h.navigation.pending!.name, 'New');
    expect(jsonDecode(h.stored!)['name'], 'New');
  });
  test(
      'direct favorite navigate/cancel retains exact commands and active transitions',
      () async {
    await h.connect();
    await h.navigation.navigate(destination(), favorite: true);
    expect(h.navigation.active!.name, 'First');
    h.navigation.navigationChanged(true);
    expect(h.navigation.active, isNotNull);
    await h.navigation.cancel();
    expect(h.navigation.active, isNull);
    expect(h.trace.where((v) => v.contains('nav:')),
        ['A:nav:fav:navigate 1', 'A:nav:clear']);
    await h.navigation.navigate(destination());
    h.navigation.navigationChanged(null);
    expect(h.navigation.active, isNull);
  });
  test('failed cancellation clears only the captured active presentation',
      () async {
    await h.connect();
    h.navigation.setActive(destination());
    h.wire.onWrite = (_) async => h.wire.reply('nav:error');
    await expectLater(h.navigation.cancel(),
        throwsA('Failed to cancel navigation, response: nav:error'));
    expect(h.navigation.active, isNull);
  });
  for (final operation in [
    'navigate',
    'favorite',
    'cancel',
    'list',
    'save',
    'delete',
    'rename'
  ]) {
    test('$operation cannot publish or continue after same-ID replacement',
        () async {
      await h.connect();
      final oldWire = h.wire;
      final gate = Completer<void>();
      oldWire.onWrite = (_) async {
        await gate.future;
        oldWire.reply(operation == 'list' ? 'nav:fav:count:0' : 'nav:ok');
      };
      final Future<dynamic> action = switch (operation) {
        'navigate' => h.navigation.navigate(destination()),
        'favorite' => h.navigation.navigate(destination(), favorite: true),
        'cancel' => h.navigation.cancel(),
        'list' => h.navigation.listFavorites(),
        'save' => h.navigation.saveFavorite(destination()),
        'delete' => h.navigation.deleteFavorite('1'),
        _ => h.navigation.renameFavorite(destination(), 'New'),
      };
      final failed = expectLater(action, throwsStateError);
      await flush();
      h.device.drop();
      await flush();
      await h.connect('A');
      h.navigation.setActive(destination('Replacement'));
      gate.complete();
      await failed;
      expect(h.navigation.active!.name, 'Replacement');
      expect(h.trace.where((v) => v.contains('nav:')), hasLength(1));
    });
  }
  test(
      'favorite save/delete/rename preserve permissive ACK and delete-add order',
      () async {
    await h.connect();
    h.wire.onWrite = (command) async => h.wire.reply(
        command.startsWith('nav:fav:add') ? 'unexpected:last-id' : 'nav:ok');
    expect(await h.navigation.saveFavorite(destination()), 'last-id');
    await h.navigation.deleteFavorite('1');
    expect(await h.navigation.renameFavorite(destination(), 'New'), 'last-id');
    expect(h.trace.where((v) => v.contains('nav:')), [
      'A:nav:fav:add 1.0,2.0,First',
      'A:nav:fav:delete 1',
      'A:nav:fav:delete 1',
      'A:nav:fav:add 1.0,2.0,New'
    ]);
  });
  test(
      'favorite list, keycard list, capability list and single command share one FIFO',
      () async {
    await h.connect();
    final held = Completer<void>();
    h.wire.onWrite = (command) async {
      if (command == 'nav:fav:list') {
        await held.future;
        h.wire.reply('nav:fav:count:2');
        h.wire.reply('nav:fav:1:1,2,First');
        h.wire.reply('nav:fav:2:3,4,City, Center');
      } else if (command == 'keycard:list') {
        h.wire.reply('keycard:count:1');
        h.wire.reply('keycard:card:ab');
      } else if (command.startsWith('cap:')) {
        h.wire.reply('cap:count:1');
        h.wire.reply('cap:nav:dest args');
      } else {
        h.wire.reply('nav:ok');
      }
    };
    final favorites = h.navigation.listFavorites();
    final keycards = h.actions.listKeycards();
    final capabilities =
        queries.getLsCapabilitiesCommand(h.device, h.repos['A']!, 'nav');
    final navigating = h.navigation.navigate(destination());
    await flush();
    expect(
        h.trace.where((v) =>
            v.contains(':nav:') ||
            v.contains(':keycard:') ||
            v.contains(':cap:')),
        ['A:nav:fav:list']);
    held.complete();
    expect((await favorites).map((d) => d.name), ['First', 'City, Center']);
    expect(await keycards, ['ab']);
    expect(await capabilities, ['dest']);
    await navigating;
    expect(h.trace.where((v) => !v.contains('target:')), [
      'A:nav:fav:list',
      'A:keycard:list',
      'A:cap:nav',
      'A:nav:dest 1.0,2.0,First'
    ]);
  });
  test('queued navigation cannot write after pending replacement', () async {
    await h.connect();
    final held = Completer<void>();
    h.wire.onWrite = (command) async {
      if (command == 'keycard:list') {
        await held.future;
        h.wire.reply('keycard:count:0');
      } else {
        h.wire.reply('nav:ok');
      }
    };
    final list = h.actions.listKeycards();
    await h.navigation.setPending(destination());
    final dispatch = h.navigation.dispatchPending();
    await h.navigation.setPending(destination('New'));
    held.complete();
    await list;
    await dispatch;
    expect(h.trace, ['A:keycard:list']);
    expect(h.navigation.pending!.name, 'New');
  });
  test('list failure cleans subscription and FIFO recovers', () async {
    await h.connect();
    h.wire.onWrite = (_) async => h.wire.reply('nav:error');
    await expectLater(h.navigation.listFavorites(),
        throwsA(isA<ExtendedResponseFormatException>()));
    expect(h.wire.responses.hasListener, false);
    h.wire.onWrite = (_) async => h.wire.reply('nav:fav:count:0');
    expect(await h.navigation.listFavorites(), isEmpty);
    expect(h.wire.responses.hasListener, false);
  });
  test(
      'non-ASCII name still fails ASCII transport rather than changing encoding',
      () async {
    await h.connect();
    await expectLater(
        h.navigation.navigate(destination('é')), throwsA(isA<ArgumentError>()));
    expect(h.wire.responses.hasListener, false);
    expect(h.trace, isEmpty);
  });
  for (final transition in ['B', 'same-ID', 'disconnect', 'dispose']) {
    test('notification enable wait rejects $transition before writing',
        () async {
      await h.connect();
      final wire = h.wire..isNotifying = false;
      wire.notifyGate = Completer<void>();
      final saving = expectLater(
          h.navigation.saveFavorite(destination()), throwsStateError);
      await flush();
      if (transition == 'B') {
        await h.connect('B');
      }
      if (transition == 'same-ID') {
        h.device.drop();
        await flush();
        await h.connect('A');
      }
      if (transition == 'disconnect') {
        h.device.drop();
        await flush();
      }
      if (transition == 'dispose') {
        h.navigation.dispose();
      }
      wire.notifyGate!.complete();
      await saving;
      expect(h.trace.where((v) => v.contains('nav:')), isEmpty);
      expect(wire.responses.hasListener, false);
    });
  }
  for (final cancel in [false, true]) {
    test(
        '${cancel ? 'cancel' : 'navigate'} old ACK cannot replace newer active request',
        () async {
      await h.connect();
      h.navigation.setActive(destination());
      final held = Completer<void>();
      h.wire.onWrite = (_) async {
        await held.future;
        h.wire.reply('nav:ok');
      };
      final old = cancel
          ? h.navigation.cancel()
          : h.navigation.navigate(destination('Old'));
      await flush();
      h.navigation.setActive(destination('New'));
      held.complete();
      await old;
      expect(h.navigation.active!.name, 'New');
    });
  }
  test(
      'new connection dispatches retained pending once after old connection ACK',
      () async {
    await h.connect();
    await h.navigation.setPending(destination());
    final oldWire = h.wire;
    final gate = Completer<void>();
    oldWire.onWrite = (_) async {
      await gate.future;
      oldWire.reply('nav:ok');
    };
    final first = h.navigation.dispatchPending();
    await flush();
    await h.connect('B');
    final second = h.navigation.dispatchPending();
    await h.navigation.dispatchPending();
    gate.complete();
    await first;
    await second;
    expect(h.navigation.pending, isNull);
    expect(h.navigation.active!.name, 'First');
    expect(h.trace.where((v) => v.contains('nav:dest')),
        ['A:nav:dest 1.0,2.0,First', 'B:nav:dest 1.0,2.0,First']);
  });
  test('pending clear awaiting storage cannot erase a newer request', () async {
    await h.connect();
    await h.navigation.setPending(destination());
    final gate = Completer<void>();
    h.saveHook = (json) async {
      if (json == null) await gate.future;
    };
    final dispatch = h.navigation.dispatchPending();
    await flush();
    expect(h.navigation.pending, isNull);
    final newer = h.navigation.setPending(destination('New'));
    gate.complete();
    await dispatch;
    await newer;
    expect(h.navigation.pending!.name, 'New');
    expect(jsonDecode(h.stored!)['name'], 'New');
  });
  test('offline cancel preserves active-card dismissal without a wire write',
      () async {
    await h.connect();
    h.navigation.setActive(destination());
    h.device.drop();
    await flush();
    await expectLater(h.navigation.cancel(), throwsStateError);
    expect(h.navigation.active, isNull);
    expect(h.trace.where((v) => v.contains('nav:')), isEmpty);
  });
  for (final favorite in [false, true]) {
    for (final succeeds in [false, true]) {
      test(
          'mixed pending to ${favorite ? 'favorite' : 'direct'} ${succeeds ? 'success retires pending without replay' : 'failure retains pending for retry'}',
          () async {
        await h.connect();
        await h.navigation.setPending(destination('PendingA', '1'));
        final wire = h.wire;
        final oldGate = Completer<void>();
        final newGate = Completer<void>();
        wire.onWrite = (command) async {
          if (command == 'nav:dest 1.0,2.0,PendingA') {
            await oldGate.future;
            wire.reply('nav:ok');
          } else {
            await newGate.future;
            wire.reply(succeeds ? 'nav:ok' : 'nav:error');
          }
        };
        final pending = h.navigation.dispatchPending();
        await flush();
        final selected = h.navigation
            .navigate(destination('SelectedB', '2'), favorite: favorite);
        final settled =
            succeeds ? selected : expectLater(selected, throwsA(isA<String>()));
        await flush();
        expect(h.trace, ['A:nav:dest 1.0,2.0,PendingA']);
        oldGate.complete();
        await pending;
        await flush();
        expect(h.navigation.active, isNull);
        expect(h.navigation.pending!.name, 'PendingA');
        expect(jsonDecode(h.stored!)['name'], 'PendingA');
        expect(h.trace, [
          'A:nav:dest 1.0,2.0,PendingA',
          favorite ? 'A:nav:fav:navigate 2' : 'A:nav:dest 1.0,2.0,SelectedB'
        ]);
        newGate.complete();
        await settled;
        expect(h.navigation.active?.name, succeeds ? 'SelectedB' : null);
        final pendingAfterSelection = h.navigation.pending?.name;
        final persistedAfterSelection = jsonDecode(h.stored ?? 'null')?['name'];
        final savesAfterSelection = h.saves.length;
        expect(wire.responses.hasListener, false);
        await h.connect('Next');
        // Exercise restoration as well as the next firmware-ready callback:
        // the retired destination must not survive in either memory or storage.
        await h.navigation.restorePending();
        h.navigation.firmwareIdentified(h.session.currentConnection!,
            const FirmwareSnapshot(isLibrescoot: true));
        await flush();
        expect({
          'pending after selection': pendingAfterSelection,
          'persisted after selection': persistedAfterSelection,
          'next connection writes': h.trace
              .where((command) => command.startsWith('Next:nav:'))
              .toList(),
        }, {
          'pending after selection': succeeds ? null : 'PendingA',
          'persisted after selection': succeeds ? null : 'PendingA',
          'next connection writes':
              succeeds ? <String>[] : ['Next:nav:dest 1.0,2.0,PendingA'],
        });
        expect(savesAfterSelection, succeeds ? 2 : 1);
      });
    }
  }

  for (final favorite in [false, true]) {
    final kind = favorite ? 'favorite' : 'direct';
    for (final replacement in [
      'pending',
      'direct',
      'favorite',
      'cancel',
      'active',
      'session'
    ]) {
      test('mixed $kind publication preserves reentrant $replacement request',
          () async {
        await h.connect();
        await h.navigation.setPending(destination('PendingA'));
        var replaced = false;
        Future<void>? replacing;
        h.onChanged = () {
          if (replaced || h.navigation.active?.name != 'SelectedB') return;
          replaced = true;
          replacing = switch (replacement) {
            'pending' => h.navigation.setPending(destination('NewC')),
            'direct' => h.navigation.navigate(destination('NewC')),
            'favorite' =>
              h.navigation.navigate(destination('NewC', '3'), favorite: true),
            'cancel' => h.navigation.cancel(),
            'session' => h.connect('Next'),
            _ => Future.sync(() => h.navigation.setActive(destination('NewC'))),
          };
        };
        await h.navigation
            .navigate(destination('SelectedB', '2'), favorite: favorite);
        await replacing;
        expect(replaced, true);
        final newerNavigation =
            replacement == 'direct' || replacement == 'favorite';
        expect(
            h.navigation.pending?.name,
            replacement == 'pending'
                ? 'NewC'
                : newerNavigation
                    ? null
                    : 'PendingA');
        expect(jsonDecode(h.stored ?? 'null')?['name'],
            h.navigation.pending?.name);
        expect(
            h.navigation.active?.name,
            replacement == 'cancel'
                ? null
                : newerNavigation || replacement == 'active'
                    ? 'NewC'
                    : 'SelectedB');
        // Only the newer successful navigation can retire A. The old B
        // completion must not append a removal after another publication.
        expect(h.saves.where((json) => json == null).length,
            newerNavigation ? 1 : 0);
      });
    }
    for (final transition in [
      'pending',
      'different session',
      'same-ID session'
    ]) {
      test('mixed $kind delayed removal preserves newer pending on $transition',
          () async {
        await h.connect();
        await h.navigation.setPending(destination('PendingA'));
        final held = Completer<void>();
        h.saveHook = (json) async {
          if (json == null) await held.future;
        };
        final selected = h.navigation
            .navigate(destination('SelectedB', '2'), favorite: favorite);
        await flush();
        expect(h.navigation.active!.name, 'SelectedB');
        expect(h.navigation.pending, isNull);
        expect(h.saves, hasLength(2));
        if (transition == 'different session') await h.connect('Next');
        if (transition == 'same-ID session') {
          h.device.drop();
          await flush();
          await h.connect('A');
        }
        final newer = h.navigation.setPending(destination('NewC'));
        final publications = h.publications;
        held.complete();
        await selected;
        await newer;
        expect(h.navigation.pending!.name, 'NewC');
        expect(jsonDecode(h.stored!)['name'], 'NewC');
        expect(h.saves.map((json) => jsonDecode(json ?? 'null')?['name']),
            ['PendingA', null, 'NewC']);
        expect(h.publications, publications + 1);
      });
    }
    for (final transition in [
      'new pending',
      'cancel pending',
      'different session',
      'same-ID session',
      'disconnect',
      'dispose'
    ]) {
      test('mixed $kind held ACK cannot retire pending after $transition',
          () async {
        await h.connect();
        await h.navigation.setPending(destination('PendingA'));
        final wire = h.wire;
        final held = Completer<void>();
        wire.onWrite = (_) async {
          await held.future;
          wire.reply('nav:ok');
        };
        final selected = h.navigation
            .navigate(destination('SelectedB', '2'), favorite: favorite);
        final settled = ['new pending', 'cancel pending'].contains(transition)
            ? selected
            : expectLater(selected, throwsStateError);
        await flush();
        if (transition == 'new pending') {
          await h.navigation.setPending(destination('NewC'));
        }
        if (transition == 'cancel pending') await h.navigation.setPending(null);
        if (transition == 'different session') await h.connect('Next');
        if (transition == 'same-ID session') {
          h.device.drop();
          await flush();
          await h.connect('A');
        }
        if (transition == 'disconnect') {
          h.device.drop();
          await flush();
        }
        if (transition == 'dispose') h.navigation.dispose();
        held.complete();
        await settled;
        expect(h.navigation.active, isNull);
        expect(
            h.navigation.pending?.name,
            switch (transition) {
              'new pending' => 'NewC',
              'cancel pending' => null,
              _ => 'PendingA',
            });
        expect(jsonDecode(h.stored ?? 'null')?['name'],
            h.navigation.pending?.name);
        expect(h.saves.where((json) => json == null).length,
            transition == 'cancel pending' ? 1 : 0);
      });
    }
    test('offline $kind selection preserves pending and active state',
        () async {
      await h.navigation.setPending(destination('PendingA'));
      h.navigation.setActive(destination('Active'));
      await expectLater(
          h.navigation
              .navigate(destination('SelectedB', '2'), favorite: favorite),
          throwsStateError);
      expect(h.navigation.pending!.name, 'PendingA');
      expect(h.navigation.active!.name, 'Active');
      expect(h.saves, hasLength(1));
      expect(h.trace, isEmpty);
    });
    test('$kind without pending does not introduce persistence effects',
        () async {
      await h.connect();
      await h.navigation
          .navigate(destination('SelectedB', '2'), favorite: favorite);
      expect(h.navigation.active!.name, 'SelectedB');
      expect(h.saves, isEmpty);
    });
    test(
        'mixed $kind persistence failure propagates without poisoning newer pending',
        () async {
      await h.connect();
      await h.navigation.setPending(destination('PendingA'));
      h.saveHook = (json) async {
        if (json == null) throw StateError('storage failed');
      };
      await expectLater(
          h.navigation
              .navigate(destination('SelectedB', '2'), favorite: favorite),
          throwsStateError);
      // As for pending dispatch, acknowledged navigation is not rolled back
      // when storage fails, nor is already-written persistent state fabricated.
      expect(h.navigation.active!.name, 'SelectedB');
      expect(h.navigation.pending, isNull);
      expect(jsonDecode(h.stored!)['name'], 'PendingA');
      await h.navigation.setPending(destination('NewC'));
      expect(jsonDecode(h.stored!)['name'], 'NewC');
    });
  }
  for (final succeeds in [false, true]) {
    test(
        'mixed pending to cancel ${succeeds ? 'success' : 'failure'} retains separate pending request',
        () async {
      await h.connect();
      await h.navigation.setPending(destination('PendingA'));
      h.navigation.setActive(destination('Active'));
      final wire = h.wire;
      final held = Completer<void>();
      wire.onWrite = (command) async {
        if (command.startsWith('nav:dest')) await held.future;
        wire.reply(
            command == 'nav:clear' && !succeeds ? 'nav:error' : 'nav:ok');
      };
      final dispatch = h.navigation.dispatchPending();
      await flush();
      final cancel = h.navigation.cancel();
      final settled =
          succeeds ? cancel : expectLater(cancel, throwsA(isA<String>()));
      held.complete();
      await dispatch;
      await settled;
      expect(h.navigation.active, isNull);
      expect(h.navigation.pending!.name, 'PendingA');
      expect(jsonDecode(h.stored!)['name'], 'PendingA');
      expect(h.saves, hasLength(1));
      await h.navigation.setPending(null);
      expect(h.stored, isNull);
    });
  }
}
