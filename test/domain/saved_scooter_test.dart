import 'dart:convert';

import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import '../support/persistence_fakes.dart';
import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/domain/saved_scooter.dart';

void main() {
  late MemoryPreferences prefs;
  late RecordingBackgroundService service;
  SharedPreferencesAsyncPlatform? previousPrefs;
  FlutterBackgroundServicePlatform? previousService;

  setUp(() {
    previousPrefs = SharedPreferencesAsyncPlatform.instance;
    try {
      previousService = FlutterBackgroundServicePlatform.instance;
    } catch (_) {
      previousService = null;
    }
    prefs = MemoryPreferences();
    service = RecordingBackgroundService();
    SharedPreferencesAsyncPlatform.instance = prefs;
    FlutterBackgroundServicePlatform.instance = service;
  });
  tearDown(() async {
    await drainPreferenceWrites();
    SharedPreferencesAsyncPlatform.instance = previousPrefs;
    // The service API cannot restore an unregistered (null) implementation.
    if (previousService != null) {
      FlutterBackgroundServicePlatform.instance = previousService!;
    }
  });

  test('JSON pins every field, nested shape and microsecond precision', () {
    const micros = 1700000000123456;
    final scooter = SavedScooter(
      id: 'outer-id',
      name: 'Commuter',
      color: 3,
      lastPing: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
      autoConnect: false,
      lastPrimarySOC: 91,
      lastSecondarySOC: 82,
      lastCbbSOC: 73,
      lastAuxSOC: 64,
      lastLocation: const LatLng(52.5, 13.4),
      lastAddress: 'A street',
      handlebarsLocked: false,
      isLibrescoot: true,
      supportsHibernateFor: false,
      supportsApnConfig: true,
      cachedDestinations: [
        NavDestination(
          location: const LatLng(51.2, 12.3),
          name: 'Desk',
          id: 'dest',
          type: SpecialDestinationType.work,
        )
      ],
    );
    final expected = <String, dynamic>{
      'id': 'outer-id',
      'name': 'Commuter',
      'color': 3,
      'lastPing': micros,
      'autoConnect': false,
      'lastPrimarySOC': 91,
      'lastSecondarySOC': 82,
      'lastCbbSOC': 73,
      'lastAuxSOC': 64,
      'lastLocation': {
        'coordinates': [13.4, 52.5]
      },
      'lastAddress': 'A street',
      'handlebarsLocked': false,
      'isLibrescoot': true,
      'supportsHibernateFor': false,
      'supportsApnConfig': true,
      'cachedDestinations': [
        {
          'latitude': 51.2,
          'longitude': 12.3,
          'name': 'Desk',
          'id': 'dest',
          'type': 'work',
        }
      ],
    };
    expect(scooter.toJson(), expected);
    final restored = SavedScooter.fromJson('outer-id', jsonDecode(jsonEncode(scooter)) as Map<String, dynamic>);
    expect(restored.toJson(), expected);
    expect(restored.lastPing.microsecondsSinceEpoch, micros);
    expect(restored.lastPing.isUtc, isFalse);
    expect(restored.cachedDestinations!.single.type, SpecialDestinationType.work);
  });

  test('missing fields use constructor defaults and current time', () {
    final before = DateTime.now();
    final scooter = SavedScooter.fromJson('key', {'id': 'ignored'});
    final after = DateTime.now();
    expect(scooter.id, 'key');
    expect(scooter.name, 'Scooter Pro');
    expect(scooter.color, 1);
    expect(scooter.autoConnect, isTrue);
    expect(scooter.lastPing.microsecondsSinceEpoch,
        inInclusiveRange(before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    final json = scooter.toJson();
    for (final key in [
      'lastPrimarySOC',
      'lastSecondarySOC',
      'lastCbbSOC',
      'lastAuxSOC',
      'lastLocation',
      'lastAddress',
      'handlebarsLocked',
      'isLibrescoot',
      'supportsHibernateFor',
      'supportsApnConfig',
      'cachedDestinations'
    ]) {
      expect(json.containsKey(key), isTrue, reason: key);
      expect(json[key], isNull, reason: key);
    }
  });

  for (final flag in <bool?>[null, false, true]) {
    test('cached capability flags preserve $flag, not a truthy default', () {
      final scooter = SavedScooter.fromJson('id', {
        'isLibrescoot': flag,
        'supportsHibernateFor': flag,
        'supportsApnConfig': flag,
        'handlebarsLocked': flag,
      });
      expect(scooter.isLibrescoot, flag);
      expect(scooter.supportsHibernateFor, flag);
      expect(scooter.supportsApnConfig, flag);
      expect(scooter.handlebarsLocked, flag);
      for (final key in ['isLibrescoot', 'supportsHibernateFor', 'supportsApnConfig', 'handlebarsLocked']) {
        expect(scooter.toJson()[key], flag);
      }
    });
  }

  test('explicit null defaults name/color/autoConnect but null timestamp throws', () {
    final scooter = SavedScooter.fromJson('id', {
      'name': null,
      'color': null,
      'autoConnect': null,
    });
    expect(scooter.name, 'Scooter Pro');
    expect(scooter.color, 1);
    expect(scooter.autoConnect, isTrue);
    expect(() => SavedScooter.fromJson('id', {'lastPing': null}), throwsA(isA<TypeError>()));
  });

  test('empty destination cache stays distinct from an unknown cache', () {
    expect(SavedScooter.fromJson('id', {}).cachedDestinations, isNull);
    expect(SavedScooter.fromJson('id', {'cachedDestinations': []}).toJson()['cachedDestinations'], isEmpty);
  });

  test('setters persist existing entry and preserve sibling and unrelated preferences', () async {
    final scooter = SavedScooter(id: 'id');
    prefs.seed({
      'id': scooter,
      'sibling': {'name': 'Untouched'}
    });
    prefs.values['unrelated'] = 'keep';
    final changes = <void Function()>[
      () => scooter.name = 'Changed',
      () => scooter.color = 4,
      () => scooter.lastPing = DateTime.fromMicrosecondsSinceEpoch(1234567),
      () => scooter.lastPrimarySOC = 10,
      () => scooter.lastSecondarySOC = 20,
      () => scooter.lastCbbSOC = 30,
      () => scooter.lastAuxSOC = 40,
      () => scooter.lastLocation = const LatLng(1, 2),
      () => scooter.lastAddress = 'Address',
      () => scooter.handlebarsLocked = true,
      () => scooter.isLibrescoot = false,
      () => scooter.supportsHibernateFor = true,
      () => scooter.supportsApnConfig = false,
      () => scooter.cachedDestinations = [],
    ];
    for (final change in changes) {
      final writes = prefs.writes;
      change();
      await drainPreferenceWrites();
      expect(prefs.writes, writes + 1);
      expect(prefs.saved['id'], scooter.toJson());
      expect(prefs.saved['sibling'], {'name': 'Untouched'});
      expect(prefs.values['unrelated'], 'keep');
    }
    expect(service.updates, isEmpty);
  });

  test('nullable setters clear cached fields and location clears address', () async {
    final scooter = SavedScooter(
        id: 'id',
        lastAddress: 'Old address',
        lastPrimarySOC: 1,
        lastSecondarySOC: 2,
        lastCbbSOC: 3,
        lastAuxSOC: 4,
        handlebarsLocked: true,
        isLibrescoot: true,
        supportsHibernateFor: true,
        supportsApnConfig: true,
        cachedDestinations: []);
    prefs.seed({'id': scooter});
    scooter.lastLocation = const LatLng(1, 2);
    await drainPreferenceWrites();
    expect(scooter.lastAddress, isNull);
    expect(prefs.saved['id']['lastAddress'], isNull);
    for (final clear in <void Function()>[
      () => scooter.lastPrimarySOC = null,
      () => scooter.lastSecondarySOC = null,
      () => scooter.lastCbbSOC = null,
      () => scooter.lastAuxSOC = null,
      () => scooter.lastLocation = null,
      () => scooter.lastAddress = null,
      () => scooter.handlebarsLocked = null,
      () => scooter.isLibrescoot = null,
      () => scooter.supportsHibernateFor = null,
      () => scooter.supportsApnConfig = null,
      () => scooter.cachedDestinations = null,
    ]) {
      clear();
      await drainPreferenceWrites();
      expect(prefs.saved['id'], scooter.toJson());
    }
  });

  test('autoConnect persists and notifies even when assigned the same value', () async {
    final scooter = SavedScooter(id: 'id');
    prefs.seed({'id': scooter});
    for (var i = 0; i < 2; i++) {
      scooter.autoConnect = false;
      await drainPreferenceWrites();
      expect(prefs.saved['id']['autoConnect'], isFalse);
    }
    expect(prefs.writes, 2);
    expect(
        service.updates,
        List.filled(2, {
          'method': 'update',
          'args': {'updateSavedScooters': true},
        }));
  });

  test('new or forgotten instances cannot create entries through setters', () async {
    final scooter = SavedScooter(id: 'forgotten');
    scooter.name = 'New';
    await drainPreferenceWrites();
    expect(prefs.values.containsKey('savedScooters'), isFalse);
    prefs.seed({
      'survivor': {'name': 'Keep'}
    });
    scooter.lastPing = DateTime.now();
    scooter.autoConnect = false;
    await drainPreferenceWrites();
    expect(prefs.saved, {
      'survivor': {'name': 'Keep'}
    });
    expect(prefs.writes, 0);
    expect(service.updates, hasLength(1));
  });
}
