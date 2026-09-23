import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:scooter_flutter/scooter_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scooter_core/scooter_core.dart';

class Record extends Fake implements SavedScooterRecord {
  @override
  bool autoConnect = true;
}

class Storage extends Fake implements ScooterStorage<Record> {
  Storage(this.trace);
  final List<String> trace;
  Completer<void>? gate;
  @override
  Map<String, Record> scooters = {'A': Record()};
  @override
  Future<void> load() async {
    trace.add('load');
    await gate?.future;
  }

  @override
  Record? getMostRecent() {
    trace.add('select');
    return scooters.values.firstOrNull;
  }
}

class Bluetooth extends Fake implements FlutterBluePlusMockable {
  final scans = StreamController<bool>.broadcast();
  int listeners = 0;
  @override
  Stream<bool> get isScanning {
    listeners++;
    return scans.stream;
  }
}

// ignore: must_be_immutable
class Preferences extends Fake implements SharedPreferencesAsync {
  Preferences(this.trace);
  final List<String> trace;
  @override
  Future<bool?> getBool(String key) async {
    trace.add(key);
    return null;
  }

  @override
  Future<int?> getInt(String key) async {
    trace.add(key);
    return null;
  }
}

class SessionEffects extends Fake implements ScooterSessionEffects {
  @override
  void invalidateTelemetry() {}
}

class TelemetryEffects extends Fake implements ScooterTelemetryEffects {}

class ActionEffects extends Fake implements ScooterActionEffects {}

class Harness {
  Harness() {
    session = ScooterSession(
        flutterBluePlus: bluetooth,
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
        loadPending: () async {
          trace.add('navigation');
          return null;
        },
        savePending: (_) async {},
        changed: () {},
        failed: (error, stack) {});
    runtime = ScooterRuntime<Record>(
        session: session,
        telemetry: telemetry,
        actions: actions,
        navigation: navigation,
        settings: UserSettings(preferences: Preferences(trace)),
        store: storage,
        idOf: (_) => 'A',
        cacheOf: (_) => const CachedTelemetry(primarySOC: 42),
        presentCache: (record, {required initial}) =>
            trace.add('present:$initial'),
        changed: () => trace.add('changed'),
        savedChanged: () => trace.add('saved'),
        manualTargetHeartbeat: (_) => trace.add('heartbeat'),
        scanningChanged: (value) => trace.add('scan:$value'),
        isScanning: () => false,
        readLocation: () async => null,
        saveLocation: (id, location) {},
        publishDisconnected: () {},
        deviceFromId: (_) => throw StateError('unexpected device'));
  }
  final trace = <String>[];
  final bluetooth = Bluetooth();
  late final storage = Storage(trace);
  late final ScooterSession session;
  late final ScooterTelemetry telemetry;
  late final ScooterActions actions;
  late final NavigationRuntime navigation;
  late final ScooterRuntime<Record> runtime;
  void dispose() {
    runtime.dispose();
    actions.dispose();
    navigation.dispose();
    telemetry.dispose();
    session.dispose();
  }
}

void main() {
  test(
      'standalone shared runtime owns ordered restore and polling without app models',
      () {
    fakeAsync((time) {
      final h = Harness();
      final first = h.runtime.initialize();
      expect(identical(first, h.runtime.initialize()), isTrue);
      time.flushMicrotasks();
      expect(h.trace, [
        'load',
        'select',
        'saved',
        'present:true',
        'changed',
        'navigation',
        'autoUnlockThreshold',
        'biometrics',
        'autoUnlock',
        'openSeatOnUnlock',
        'hazardLocking',
        'unlockedHandlebarsWarning'
      ]);
      expect(h.telemetry.battery.primarySOC, 42);
      expect(h.bluetooth.listeners, 1);
      expect(time.pendingTimers, hasLength(4));
      h.runtime.dispose();
      time.flushMicrotasks();
      expect(h.bluetooth.scans.hasListener, isFalse);
      expect(time.pendingTimers, isEmpty);
      h.runtime.initialize();
      time.flushMicrotasks();
      expect(h.bluetooth.listeners, 1);
      h.dispose();
    });
  });
  test(
      'runtime disposal guards delayed load even while the supplied session remains alive',
      () {
    fakeAsync((time) {
      final h = Harness();
      h.storage.gate = Completer<void>();
      h.runtime.initialize();
      time.flushMicrotasks();
      h.runtime.dispose();
      h.storage.gate!.complete();
      time.flushMicrotasks();
      expect(h.session.isDisposed, isFalse);
      expect(h.trace, ['load']);
      expect(time.pendingTimers, isEmpty);
      h.dispose();
    });
  });
  test(
      'refetch owns cache phase without repeating navigation or settings restoration',
      () {
    fakeAsync((time) {
      final h = Harness();
      h.runtime.initialize();
      time.flushMicrotasks();
      h.trace.clear();
      h.runtime.refetchSavedScooters();
      time.flushMicrotasks();
      expect(h.trace, ['load', 'select', 'saved', 'present:false', 'changed']);
      h.trace.clear();
      h.storage.scooters.clear();
      h.runtime.refetchSavedScooters();
      time.flushMicrotasks();
      expect(h.trace, ['load', 'select', 'present:false', 'changed']);
      expect(h.telemetry.battery.primarySOC, isNull);
      h.dispose();
    });
  });
}
