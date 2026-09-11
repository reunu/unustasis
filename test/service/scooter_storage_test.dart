import 'dart:convert';

import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/service/scooter_storage.dart';

import '../support/persistence_fakes.dart';

void main() {
  late MemoryPreferences prefs;
  late RecordingBackgroundService service;
  late ScooterStorage storage;
  SharedPreferencesAsyncPlatform? previousPrefs;
  FlutterBackgroundServicePlatform? previousService;

  SavedScooter scooter(String id, {bool autoConnect = true, int ping = 100}) =>
      SavedScooter(id: id, autoConnect: autoConnect, lastPing: DateTime.fromMicrosecondsSinceEpoch(ping));

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
    storage = ScooterStorage();
  });
  tearDown(() async {
    await drainPreferenceWrites();
    SharedPreferencesAsyncPlatform.instance = previousPrefs;
    if (previousService != null) {
      FlutterBackgroundServicePlatform.instance = previousService!;
    }
  });

  test('load uses savedScooters key, outer IDs and skips non-map values', () async {
    prefs.seed({
      'a': {'id': 'wrong', 'name': 'Alpha', 'lastPing': 1234567},
      'number': 42,
      'list': [],
      'null': null,
      'text': 'invalid',
      'b': {'autoConnect': false},
    });
    storage.scooters['old'] = scooter('old');
    await storage.load();
    expect(storage.scooters.keys, ['a', 'b']);
    expect(storage.scooters['a']!.id, 'a');
    expect(storage.scooters['a']!.name, 'Alpha');
    expect(storage.scooters['a']!.lastPing.microsecondsSinceEpoch, 1234567);
    expect(storage.scooters['b']!.autoConnect, isFalse);
    expect(prefs.writes, 0);
  });

  test('missing preference preserves existing in-memory entries (current behavior)', () async {
    final old = scooter('old');
    storage.scooters['old'] = old;
    await storage.load();
    expect(storage.scooters, {'old': same(old)});
    expect(prefs.writes, 0);
  });

  test('empty JSON object clears existing in-memory entries', () async {
    prefs.seed({});
    storage.scooters['old'] = scooter('old');
    await storage.load();
    expect(storage.scooters, isEmpty);
  });

  for (final invalid in ['not json', '[]', 'null']) {
    test('load swallows invalid root $invalid and clears local entries', () async {
      prefs.values['savedScooters'] = invalid;
      storage.scooters['old'] = scooter('old');
      await storage.load();
      expect(storage.scooters, isEmpty);
      expect(prefs.values['savedScooters'], invalid);
      expect(prefs.writes, 0);
    });
  }

  test('malformed map aborts load after valid prefix (current partial-load flaw)', () async {
    prefs.seed({
      'first': {'name': 'Valid'},
      'bad': {'lastPing': null},
      'last': {'name': 'Also valid'},
    });
    await storage.load();
    expect(storage.scooters.keys, ['first']);
    expect(prefs.saved.keys, ['first', 'bad', 'last']);
    expect(prefs.writes, 0);
  });

  test('save replaces whole saved map, retaining unrelated preference keys', () async {
    prefs.seed({'stale': {}});
    prefs.values['unrelated'] = 'keep';
    final a = scooter('a');
    final b = scooter('b', autoConnect: false);
    storage.scooters = {'a': a, 'b': b};
    await storage.save();
    expect(prefs.saved, {'a': a.toJson(), 'b': b.toJson()});
    expect(prefs.values.keys.toSet(), {'savedScooters', 'unrelated'});
    expect(prefs.values['unrelated'], 'keep');
    expect(prefs.writes, 1);
    storage.scooters.clear();
    await storage.save();
    expect(jsonDecode(prefs.values['savedScooters']!), {});
  });

  test('getIds lazily loads prefs, then uses non-empty local cache', () async {
    prefs.seed({
      'a': {},
      'b': {'autoConnect': false}
    });
    expect(await storage.getIds(), ['a', 'b']);
    final reads = prefs.reads;
    prefs.seed({'changed': {}});
    expect(await storage.getIds(), ['a', 'b']);
    expect(await storage.getIds(onlyAutoConnect: true), ['a']);
    expect(prefs.reads, reads);
  });

  test('getIds returns empty without a saved key and retries an empty cache', () async {
    expect(await storage.getIds(), isEmpty);
    expect(await storage.getIds(onlyAutoConnect: true), isEmpty);
    expect(prefs.reads, 0);
    prefs.seed({});
    expect(await storage.getIds(), isEmpty);
    prefs.seed({'added': {}});
    expect(await storage.getIds(), ['added']);
  });

  test('single disabled scooter remains in autoConnect IDs without mutation', () async {
    prefs.seed({
      'a': {'autoConnect': false}
    });
    expect(await storage.getIds(onlyAutoConnect: true), ['a']);
    expect(storage.scooters['a']!.autoConnect, isFalse);
    expect(prefs.saved['a']['autoConnect'], isFalse);
    expect(prefs.writes, 0);
    expect(service.updates, isEmpty);
  });

  test('filterAutoConnect copies map, retains references and special-cases singleton', () {
    final a = scooter('a', autoConnect: false);
    final b = scooter('b');
    expect(storage.filterAutoConnect({}), isEmpty);
    final single = {'a': a};
    final singleResult = storage.filterAutoConnect(single);
    expect(singleResult['a'], same(a));
    singleResult.clear();
    expect(single, hasLength(1));
    final input = {'a': a, 'b': b};
    final filtered = storage.filterAutoConnect(input);
    expect(filtered.keys, ['b']);
    expect(filtered['b'], same(b));
    expect(input, hasLength(2));
    expect(a.autoConnect, isFalse);
  });

  test('getMostRecent does not load preferences and returns null for empty cache', () {
    prefs.seed({'a': {}});
    expect(storage.getMostRecent(), isNull);
    expect(prefs.reads, 0);
  });

  test('getMostRecent re-enables and persists sole disabled scooter', () async {
    final a = scooter('a', autoConnect: false);
    storage.scooters['a'] = a;
    prefs.seed({'a': a});
    expect(storage.getMostRecent(), same(a));
    expect(a.autoConnect, isTrue);
    await drainPreferenceWrites();
    expect(prefs.saved['a']['autoConnect'], isTrue);
    expect(prefs.writes, 1);
    expect(service.updates, [
      {
        'method': 'update',
        'args': {'updateSavedScooters': true},
      }
    ]);
    expect(storage.getMostRecent(), same(a));
    await drainPreferenceWrites();
    expect(prefs.writes, 1);
  });

  test('getMostRecent excludes disabled entries and keeps first on timestamp ties', () {
    final first = scooter('first', ping: 200);
    storage.scooters = {
      'older': scooter('older', ping: 100),
      'first': first,
      'tied': scooter('tied', ping: 200),
      'disabled': scooter('disabled', ping: 300, autoConnect: false),
    };
    expect(storage.getMostRecent(), same(first));
    expect(prefs.writes, 0);
    expect(service.updates, isEmpty);
  });

  test('getMostRecent returns null with multiple disabled scooters', () {
    storage.scooters = {
      'a': scooter('a', autoConnect: false),
      'b': scooter('b', autoConnect: false),
    };
    expect(storage.getMostRecent(), isNull);
    expect(storage.scooters.values.every((s) => !s.autoConnect), isTrue);
  });

  test('add persists defaults and current ping; duplicate is a no-op', () async {
    final before = DateTime.now();
    expect(await storage.add('a'), isTrue);
    final after = DateTime.now();
    final a = storage.scooters['a']!;
    expect(a.name, 'Scooter Pro');
    expect(a.color, 0); // Storage differs from the domain constructor's 1.
    expect(a.autoConnect, isTrue);
    expect(a.lastPing.microsecondsSinceEpoch,
        inInclusiveRange(before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    expect(prefs.saved, {'a': a.toJson()});
    expect(await storage.add('a'), isFalse);
    expect(storage.scooters['a'], same(a));
    expect(prefs.writes, 1);
  });

  test('add without loading overwrites previously saved entries (current behavior)', () async {
    prefs.seed({'previous': {}});
    await storage.add('new');
    expect(prefs.saved.keys, ['new']);
  });

  test('remove persists survivors and stale setters cannot resurrect forgotten scooter', () async {
    final forgotten = scooter('forgotten');
    final survivor = scooter('survivor');
    storage.scooters = {'forgotten': forgotten, 'survivor': survivor};
    await storage.save();
    await storage.remove('forgotten');
    expect(storage.scooters.keys, ['survivor']);
    final writes = prefs.writes;
    forgotten.lastPing = DateTime.now();
    forgotten.name = 'Stale instance';
    await drainPreferenceWrites();
    expect(prefs.saved, {'survivor': survivor.toJson()});
    expect(prefs.writes, writes);
    await storage.remove('absent');
    expect(prefs.writes, writes + 1);
    await storage.remove('survivor');
    expect(prefs.values['savedScooters'], '{}');
    survivor.color = 4;
    await drainPreferenceWrites();
    expect(prefs.saved, isEmpty);
  });

  test('rename creates missing entries and persists existing entries', () async {
    await storage.rename('a', 'Alpha');
    final a = storage.scooters['a']!;
    expect(a.color, 1);
    expect(prefs.saved['a'], a.toJson());
    await storage.rename('a', 'Beta');
    await drainPreferenceWrites();
    expect(storage.scooters['a'], same(a));
    expect(a.name, 'Beta');
    expect(prefs.saved['a']['name'], 'Beta');
  });

  test('recolor missing scooter stays memory-only until save (current behavior)', () async {
    await storage.recolor('a', 4);
    expect(storage.scooters['a']!.color, 4);
    expect(prefs.values, isEmpty);
    await storage.save();
    await storage.recolor('a', 2);
    await drainPreferenceWrites();
    expect(prefs.saved['a']['color'], 2);
  });

  test('updatePing ignores missing IDs and persists a known entry asynchronously', () async {
    storage.updatePing('absent');
    expect(storage.scooters, isEmpty);
    expect(prefs.writes, 0);
    final a = scooter('a', ping: 1);
    storage.scooters['a'] = a;
    prefs.seed({'a': a});
    final before = DateTime.now();
    storage.updatePing('a');
    final after = DateTime.now();
    await drainPreferenceWrites();
    expect(a.lastPing.microsecondsSinceEpoch,
        inInclusiveRange(before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    expect(prefs.saved['a']['lastPing'], a.lastPing.microsecondsSinceEpoch);
    expect(prefs.writes, 1);
  });
}
