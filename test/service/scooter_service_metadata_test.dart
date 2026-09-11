import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

class _Bluetooth extends Fake implements FlutterBluePlusMockable {}

class _Device extends Fake implements BluetoothDevice {
  _Device(String id) : remoteId = DeviceIdentifier(id);
  @override
  final DeviceIdentifier remoteId;
  @override
  bool get isConnected => false;
  @override
  Future<void> disconnect({int timeout = 35, bool queue = true, int androidDelay = 2000}) async {}
}

class _Store extends Fake implements ScooterStorage {
  _Store(this.trace);
  final List<Object> trace;
  final gates = <Completer<void>>[];
  Object? mutationError, selectionError;
  void Function()? selecting;
  String? recent = 'A';
  @override
  Map<String, SavedScooter> scooters = {
    'A': SavedScooter(id: 'A', name: 'Alpha', color: 1),
    'B': SavedScooter(id: 'B', name: 'Beta', color: 2),
  };
  Future<void> mutate(String kind, String id, Object value) async {
    trace.add('$kind:$id:$value');
    if (gates.isNotEmpty) await gates.removeAt(0).future;
    if (mutationError != null) throw mutationError!;
    trace.add('stored:$kind:$id:$value');
  }

  @override
  Future<void> rename(String id, String name) => mutate('rename', id, name);
  @override
  Future<void> recolor(String id, int color) => mutate('recolor', id, color);
  @override
  SavedScooter? getMostRecent() {
    trace.add('select');
    if (selectionError != null) throw selectionError!;
    selecting?.call();
    return scooters[recent];
  }
}

class _Service extends ScooterService {
  _Service(ScooterStorage storage, this.trace) : super(_Bluetooth(), storage: storage, initializeRuntime: false);
  final List<Object> trace;
  Object? backgroundError;
  @override
  void updateBackgroundService(dynamic data) {
    trace.add(Map<String, dynamic>.from(data as Map));
    if (backgroundError != null) throw backgroundError!;
  }
}

void _edit(ScooterService service, String kind, {String? id, String name = 'New', int color = 7}) {
  if (kind == 'rename') {
    service.renameSavedScooter(id: id, name: name);
  } else {
    service.recolorSavedScooter(id: id, color: color);
  }
}

List<Object> _publication(String kind, {bool selected = true}) => [
      if (selected) 'notify',
      if (selected && kind == 'recolor') {'scooterColor': 7},
      {
        'updateSavedScooters': true,
        if (selected) kind == 'rename' ? 'scooterName' : 'scooterColor': kind == 'rename' ? 'New' : 7
      },
      'notify',
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform? previousPreferences;
  FlutterBackgroundServicePlatform? previousBackground;
  setUp(() {
    previousPreferences = SharedPreferencesAsyncPlatform.instance;
    try {
      previousBackground = FlutterBackgroundServicePlatform.instance;
    } catch (_) {
      previousBackground = null;
    }
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    FlutterBackgroundServicePlatform.instance = RecordingBackgroundService();
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
    if (previousBackground != null) FlutterBackgroundServicePlatform.instance = previousBackground!;
  });

  for (final kind in ['rename', 'recolor']) {
    for (final mode in [
      'explicit offline selected',
      'explicit cached other',
      'explicit live other',
      'default live',
      'default retained disconnected'
    ]) {
      test('$kind preserves ID and most-recent selection: $mode', () {
        fakeAsync((time) {
          final trace = <Object>[];
          final store = _Store(trace);
          final service = _Service(store, trace);
          if (mode.contains('live') || mode.contains('retained')) service.myScooter = _Device('B');
          service.connected = mode.contains('live');
          final defaults = mode.startsWith('default');
          final selected = !mode.contains('other');
          store.recent = selected ? (defaults ? 'B' : 'A') : 'B';
          if (mode == 'explicit live other') store.recent = 'A';
          service.addListener(() => trace.add('notify'));
          final id = defaults
              ? 'B'
              : mode == 'explicit live other'
                  ? 'B'
                  : 'A';
          _edit(service, kind, id: defaults ? null : id);
          expect(
              trace, ['$kind:$id:${kind == 'rename' ? 'New' : 7}', 'stored:$kind:$id:${kind == 'rename' ? 'New' : 7}']);
          time.flushMicrotasks();
          expect(trace, [
            '$kind:$id:${kind == 'rename' ? 'New' : 7}',
            'stored:$kind:$id:${kind == 'rename' ? 'New' : 7}',
            'select',
            ..._publication(kind, selected: selected)
          ]);
          expect(service.scooterName, selected && kind == 'rename' ? 'New' : null);
          expect(service.scooterColor, selected && kind == 'recolor' ? 7 : null);
          service.dispose();
        });
      });
    }

    test('$kind missing ID warns synchronously without store or publication', () {
      fakeAsync((time) {
        final trace = <Object>[];
        final service = _Service(_Store(trace), trace);
        final logs = <LogRecord>[];
        final subscription = service.log.onRecord.listen(logs.add);
        _edit(service, kind);
        time.flushMicrotasks();
        expect(trace, isEmpty);
        expect(logs.single.level, Level.WARNING);
        expect(logs.single.message,
            "Attempted to $kind scooter, but no ID was given and we're not connected to anything!");
        subscription.cancel();
        service.dispose();
      });
    });

    test('$kind awaits mutation and selection; captures default ID but selects after storage', () {
      fakeAsync((time) {
        final trace = <Object>[];
        final store = _Store(trace);
        final gate = Completer<void>();
        store.gates.add(gate);
        final service = _Service(store, trace)..myScooter = _Device('A');
        service.addListener(() => trace.add('notify'));
        _edit(service, kind);
        time.flushMicrotasks();
        expect(trace, ['$kind:A:${kind == 'rename' ? 'New' : 7}']);
        service.myScooter = _Device('B');
        store.recent = 'B';
        store.selecting = () => scheduleMicrotask(() => trace.add('selection microtask'));
        gate.complete();
        time.flushMicrotasks();
        expect(trace, [
          '$kind:A:${kind == 'rename' ? 'New' : 7}',
          'stored:$kind:A:${kind == 'rename' ? 'New' : 7}',
          'select',
          'selection microtask',
          ..._publication(kind, selected: false)
        ]);
        service.dispose();
      });
    });

    for (final stage in ['mutation', 'selection', 'publication']) {
      test('$kind $stage failure escapes void API to caller zone without subsequent notification', () {
        fakeAsync((time) {
          final trace = <Object>[];
          final errors = <Object>[];
          final failure = StateError(stage);
          final store = _Store(trace);
          if (stage == 'mutation') store.mutationError = failure;
          if (stage == 'selection') store.selectionError = failure;
          final service = _Service(store, trace);
          // A single-record selection publishes savedChanged before projection.
          if (stage == 'publication') {
            store.scooters.remove('B');
            service.backgroundError = failure;
          }
          service.addListener(() => trace.add('notify'));
          runZonedGuarded(() => _edit(service, kind, id: 'A'), (error, stack) => errors.add(error));
          time.flushMicrotasks();
          expect(errors, [same(failure)]);
          expect(trace.whereType<Map>().length, stage == 'publication' ? 1 : 0);
          expect(trace, isNot(contains('notify')));
          expect(trace.where((item) => item == 'select').length, stage == 'mutation' ? 0 : 1);
          service.dispose();
        });
      });
    }

    test('$kind single-record selection publishes saved list before metadata', () {
      fakeAsync((time) {
        final trace = <Object>[];
        final store = _Store(trace)..scooters.remove('B');
        final service = _Service(store, trace)..addListener(() => trace.add('notify'));
        _edit(service, kind, id: 'A');
        time.flushMicrotasks();
        expect(trace.skip(3), [
          {'updateSavedScooters': true},
          ..._publication(kind)
        ]);
        service.dispose();
      });
    });
  }

  for (final reverse in [false, true]) {
    test('overlapping rename/recolor are independent; reverse completion=$reverse', () {
      fakeAsync((time) {
        final trace = <Object>[];
        final store = _Store(trace);
        final rename = Completer<void>(), recolor = Completer<void>();
        store.gates.addAll([rename, recolor]);
        final service = _Service(store, trace)..addListener(() => trace.add('notify'));
        service.renameSavedScooter(id: 'A', name: 'New');
        service.recolorSavedScooter(id: 'A', color: 7);
        expect(trace, ['rename:A:New', 'recolor:A:7']);
        (reverse ? recolor : rename).complete();
        time.flushMicrotasks();
        expect(trace.skip(2), [
          'stored:${reverse ? 'recolor:A:7' : 'rename:A:New'}',
          'select',
          ..._publication(reverse ? 'recolor' : 'rename')
        ]);
        trace.clear();
        store.recent = 'B';
        (reverse ? rename : recolor).complete();
        time.flushMicrotasks();
        expect(trace, [
          'stored:${reverse ? 'rename:A:New' : 'recolor:A:7'}',
          'select',
          ..._publication(reverse ? 'rename' : 'recolor', selected: false)
        ]);
        service.dispose();
      });
    });
  }

  for (final kind in ['rename', 'recolor']) {
    test('real storage $kind unknown ID preserves creation and persistence behavior', () async {
      final previousPrefs = SharedPreferencesAsyncPlatform.instance;
      final previousBackground = FlutterBackgroundServicePlatform.instance;
      final prefs = MemoryPreferences();
      final background = RecordingBackgroundService();
      SharedPreferencesAsyncPlatform.instance = prefs;
      FlutterBackgroundServicePlatform.instance = background;
      final trace = <Object>[];
      final store = ScooterStorage();
      final service = _Service(store, trace)..addListener(() => trace.add('notify'));
      try {
        _edit(service, kind, id: 'unknown');
        await drainPreferenceWrites();
        expect(store.scooters.keys, ['unknown']);
        expect(store.scooters['unknown']!.name, kind == 'rename' ? 'New' : 'Scooter Pro');
        expect(store.scooters['unknown']!.color, kind == 'rename' ? 1 : 7);
        expect(prefs.saved.containsKey('unknown'), kind == 'rename');
        expect(trace, [
          {'updateSavedScooters': true},
          ..._publication(kind)
        ]);
      } finally {
        service.dispose();
        SharedPreferencesAsyncPlatform.instance = previousPrefs;
        FlutterBackgroundServicePlatform.instance = previousBackground;
      }
    });
  }
  for (final kind in ['rename', 'recolor']) {
    for (final backgroundMode in [false, true]) {
      test('real $kind native payload and notifications background=$backgroundMode', () async {
        final background = FlutterBackgroundServicePlatform.instance as RecordingBackgroundService;
        final prefs = SharedPreferencesAsyncPlatform.instance as MemoryPreferences;
        final store = ScooterStorage();
        store.scooters = {'A': SavedScooter(id: 'A', name: 'Alpha', color: 1)};
        prefs.seed({'A': store.scooters['A']!.toJson()});
        final service = ScooterService(_Bluetooth(),
            storage: store, initializeRuntime: false, isInBackgroundService: backgroundMode);
        var notifications = 0;
        service.addListener(() => notifications++);
        _edit(service, kind, id: 'A');
        expect(notifications, 0);
        await drainPreferenceWrites();
        expect(notifications, 2);
        expect(
            background.updates,
            backgroundMode
                ? []
                : [
                    {
                      'method': 'update',
                      'args': {'updateSavedScooters': true}
                    },
                    if (kind == 'recolor')
                      {
                        'method': 'update',
                        'args': {'scooterColor': 7}
                      },
                    {
                      'method': 'update',
                      'args': {
                        'updateSavedScooters': true,
                        kind == 'rename' ? 'scooterName' : 'scooterColor': kind == 'rename' ? 'New' : 7
                      }
                    },
                  ]);
        expect(prefs.saved['A'][kind == 'rename' ? 'name' : 'color'], kind == 'rename' ? 'New' : 7);
        service.dispose();
      });
    }
    test('$kind no eligible most-recent record only publishes saved list', () {
      fakeAsync((time) {
        final trace = <Object>[];
        final store = _Store(trace)..recent = null;
        final service = _Service(store, trace)..addListener(() => trace.add('notify'));
        _edit(service, kind, id: 'A');
        time.flushMicrotasks();
        expect(trace.skip(3), _publication(kind, selected: false));
        service.dispose();
      });
    });
    test('real $kind single disabled record reenables autoconnect during selection', () async {
      final background = FlutterBackgroundServicePlatform.instance as RecordingBackgroundService;
      final prefs = SharedPreferencesAsyncPlatform.instance as MemoryPreferences;
      final store = ScooterStorage();
      store.scooters = {'A': SavedScooter(id: 'A', autoConnect: false)};
      prefs.seed({'A': store.scooters['A']!.toJson()});
      final trace = <Object>[];
      final service = _Service(store, trace)..addListener(() => trace.add('notify'));
      _edit(service, kind, id: 'A');
      await drainPreferenceWrites();
      expect(store.scooters['A']!.autoConnect, isTrue);
      expect(background.updates, [
        {
          'method': 'update',
          'args': {'updateSavedScooters': true}
        }
      ]);
      expect(trace, [
        {'updateSavedScooters': true},
        ..._publication(kind)
      ]);
      service.dispose();
    });
  }
}
