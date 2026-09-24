import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:scooter_flutter/scooter_runtime.dart';

import 'scooter_runtime_test.dart'
    show
        Bluetooth,
        Preferences,
        SessionEffects,
        TelemetryEffects,
        ActionEffects;

class _Record extends Fake implements SavedScooterRecord {
  _Record(this.key);
  final String key;
  @override
  bool autoConnect = true;
}

class _Device extends Fake implements BluetoothDevice {
  @override
  DeviceIdentifier get remoteId => const DeviceIdentifier('A');
  @override
  bool get isConnected => false;
  @override
  Future<void> disconnect(
      {int timeout = 35, bool queue = true, int androidDelay = 2000}) async {}
}

class _Store extends Fake implements ScooterStorage<_Record> {
  _Store(this.trace);
  final List<String> trace;
  final gate = Completer<void>();
  @override
  final scooters = {'A': _Record('A'), 'B': _Record('B')};
  @override
  Future<void> rename(String id, String name) {
    trace.add('rename:$id:$name');
    return gate.future;
  }

  @override
  Future<void> recolor(String id, int color) {
    trace.add('recolor:$id:$color');
    return gate.future;
  }

  @override
  _Record getMostRecent() {
    trace.add('select');
    return scooters['A']!;
  }
}

class _Harness {
  _Harness() {
    session = ScooterSession(
        flutterBluePlus: Bluetooth(),
        effects: SessionEffects(),
        onChanged: () {},
        findEligibleScooter: () async => null,
        isScanning: () => false,
        onStart: () {});
    telemetry = ScooterTelemetry(effects: TelemetryEffects());
    actions = ScooterActions(
        session: session,
        telemetry: telemetry,
        settings: () => const ActionSettings(),
        effects: ActionEffects());
    navigation = NavigationRuntime(
        loadPending: () async => null,
        savePending: (_) async {},
        changed: () {},
        failed: (error, stack) {});
    runtime = ScooterRuntime<_Record>(
        session: session,
        telemetry: telemetry,
        actions: actions,
        navigation: navigation,
        settings: UserSettings(preferences: Preferences(trace)),
        store: store,
        idOf: (record) => record.key,
        cacheOf: (_) => const CachedTelemetry(),
        presentCache: (_, {required initial}) {},
        changed: () => trace.add('changed'),
        savedChanged: () => trace.add('saved'),
        manualTargetHeartbeat: (_) {},
        scanningChanged: (_) {},
        isScanning: () => false,
        readLocation: () async => null,
        saveLocation: (id, location) {},
        publishDisconnected: () {},
        deviceFromId: (_) => _Device());
  }
  final trace = <String>[];
  late final store = _Store(trace);
  late final ScooterSession session;
  late final ScooterTelemetry telemetry;
  late final ScooterActions actions;
  late final NavigationRuntime navigation;
  late final ScooterRuntime<_Record> runtime;
  Future<void> edit(String kind, {String? id, bool failPublication = false}) {
    void missing() => trace.add('missing');
    void publish(bool selected) {
      trace.add('publish:$selected');
      if (failPublication) throw StateError('publication');
    }

    return kind == 'rename'
        ? runtime.renameSavedScooter(
            id: id, name: 'Name', missingId: missing, publish: publish)
        : runtime.recolorSavedScooter(
            id: id, color: 9, missingId: missing, publish: publish);
  }

  void dispose() {
    runtime.dispose();
    actions.dispose();
    navigation.dispose();
    telemetry.dispose();
    session.dispose();
  }
}

void main() {
  for (final kind in ['rename', 'recolor']) {
    for (final target in ['A', 'B', 'default']) {
      test(
          'shared $kind awaits store then selects generic record and publishes: $target',
          () async {
        final h = _Harness();
        addTearDown(h.dispose);
        if (target == 'default') h.session.device = _Device();
        var complete = false;
        final future = h
            .edit(kind, id: target == 'default' ? null : target)
            .then((_) => complete = true);
        await Future<void>.delayed(Duration.zero);
        expect(complete, isFalse);
        expect(h.trace, [
          '$kind:${target == 'default' ? 'A' : target}:${kind == 'rename' ? 'Name' : 9}'
        ]);
        h.store.gate.complete();
        await future;
        expect(
            h.trace.skip(1), ['select', 'publish:${target != 'B'}', 'changed']);
        expect(complete, isTrue);
      });
    }
    test('shared $kind missing target does not mutate or publish', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.edit(kind);
      expect(h.trace, ['missing']);
    });
    test(
        'shared $kind store failure propagates without selection or publication',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final future = h.edit(kind, id: 'A');
      final expectation = expectLater(future, throwsStateError);
      h.store.gate.completeError(StateError('store'));
      await expectation;
      expect(h.trace, ['$kind:A:${kind == 'rename' ? 'Name' : 9}']);
    });
    test('shared $kind publication failure does not notify afterward',
        () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final future = h.edit(kind, id: 'A', failPublication: true);
      final expectation = expectLater(future, throwsStateError);
      h.store.gate.complete();
      await expectation;
      expect(h.trace.skip(1), ['select', 'publish:true']);
    });
  }
}
