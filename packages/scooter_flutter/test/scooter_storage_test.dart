import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Record implements SavedScooterRecord {
  final String id;
  @override
  String name;
  @override
  int color;
  @override
  DateTime lastPing;
  bool _autoConnect = true;
  int autoConnectWrites = 0;

  Record({required this.id, String? name, int? color, DateTime? lastPing})
      : name = name ?? 'Factory fallback',
        color = color ?? 7,
        lastPing = lastPing ?? DateTime.fromMicrosecondsSinceEpoch(1);

  @override
  bool get autoConnect => _autoConnect;
  @override
  set autoConnect(bool value) {
    autoConnectWrites++;
    _autoConnect = value;
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': name,
        'paint': color,
        'ping': lastPing.microsecondsSinceEpoch,
        'connect': autoConnect,
      };
}

// Mutable test double for the immutable preferences API.
// ignore: must_be_immutable
class MemoryPreferences extends Fake implements SharedPreferencesAsync {
  final Map<String, String> values = {};
  int reads = 0;
  int writes = 0;
  bool failReads = false;
  bool failWrites = false;

  Map<String, dynamic> get saved =>
      jsonDecode(values['savedScooters']!) as Map<String, dynamic>;

  @override
  Future<String?> getString(String key) async {
    reads++;
    if (failReads) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> setString(String key, String value) async {
    writes++;
    if (failWrites) throw StateError('write failed');
    values[key] = value;
  }
}

void main() {
  late MemoryPreferences prefs;
  late ScooterStorage<Record> storage;
  late List<String> decoded;
  late List<Map<String, dynamic>> created;

  setUp(() {
    prefs = MemoryPreferences();
    decoded = [];
    created = [];
    storage = ScooterStorage<Record>(
      prefs: prefs,
      defaultName: 'Fleet custom name',
      decode: (id, json) {
        decoded.add(id);
        if (json['broken'] == true) throw FormatException('bad record');
        return Record(
          id: id,
          name: json['label'] as String?,
          color: json['paint'] as int?,
          lastPing:
              DateTime.fromMicrosecondsSinceEpoch(json['ping'] as int? ?? 1),
        )..autoConnect = json['connect'] as bool? ?? true;
      },
      create: ({required id, name, color, lastPing}) {
        created.add(
            {'id': id, 'name': name, 'color': color, 'lastPing': lastPing});
        return Record(id: id, name: name, color: color, lastPing: lastPing);
      },
    );
  });

  test('add uses injected factory, custom name, zero color and current ping',
      () async {
    prefs.values['savedScooters'] = '{"previous":{}}';
    final before = DateTime.now();
    expect(await storage.add('new'), isTrue);
    final after = DateTime.now();
    final record = storage.scooters['new']!;
    expect(created.single, {
      'id': 'new',
      'name': 'Fleet custom name',
      'color': 0,
      'lastPing': record.lastPing
    });
    expect(
        record.lastPing.microsecondsSinceEpoch,
        inInclusiveRange(
            before.microsecondsSinceEpoch, after.microsecondsSinceEpoch));
    expect(prefs.saved, {'new': record.toJson()});
    expect(await storage.add('new'), isFalse);
    expect(created, hasLength(1));
    expect(prefs.writes, 1);
    expect(prefs.reads, 0);
  });

  test('rename and recolor preserve factory omissions and persistence behavior',
      () async {
    await storage.rename('renamed', 'Custom');
    expect(created.single,
        {'id': 'renamed', 'name': 'Custom', 'color': null, 'lastPing': null});
    expect(storage.scooters['renamed']!.color, 7);
    expect(prefs.saved['renamed']['label'], 'Custom');
    await storage.recolor('painted', 9);
    expect(created.last,
        {'id': 'painted', 'name': null, 'color': 9, 'lastPing': null});
    expect(storage.scooters['painted']!.name, 'Factory fallback');
    expect(prefs.saved.keys, ['renamed']);
    final original = storage.scooters['renamed'];
    await storage.rename('renamed', 'Again');
    await storage.recolor('renamed', 4);
    expect(storage.scooters['renamed'], same(original));
    expect(created, hasLength(2));
    expect(prefs.saved['renamed']['paint'], 7);
    expect(original!.color, 4);
  });

  test('decoder gets outer ID and custom schema, skipping non-map values',
      () async {
    prefs.values['savedScooters'] = jsonEncode({
      'outer': {
        'id': 'ignored',
        'label': 'Decoded',
        'paint': 8,
        'ping': 99,
        'connect': false
      },
      'skip': [],
      'number': 3,
      'null': null,
    });
    await storage.load();
    expect(decoded, ['outer']);
    final record = storage.scooters['outer']!;
    expect(record.id, 'outer');
    expect(record.name, 'Decoded');
    expect(record.color, 8);
    expect(record.lastPing.microsecondsSinceEpoch, 99);
    expect(record.autoConnect, isFalse);
    expect(prefs.writes, 0);
  });

  test('decoder error aborts after prefix without rewriting persistence',
      () async {
    prefs.values['savedScooters'] =
        '{"first":{},"bad":{"broken":true},"last":{}}';
    await storage.load();
    expect(decoded, ['first', 'bad']);
    expect(storage.scooters.keys, ['first']);
    expect(prefs.saved.keys, ['first', 'bad', 'last']);
    expect(prefs.writes, 0);
  });

  test(
      'missing preference keeps memory; invalid roots and read errors clear it',
      () async {
    final old = Record(id: 'old');
    storage.scooters = {'old': old};
    await storage.load();
    expect(storage.scooters['old'], same(old));
    for (final invalid in ['not json', '[]', 'null', '{}']) {
      storage.scooters = {'old': old};
      prefs.values['savedScooters'] = invalid;
      await storage.load();
      expect(storage.scooters, isEmpty);
    }
    storage.scooters = {'old': old};
    prefs.failReads = true;
    await storage.load();
    expect(storage.scooters, isEmpty);
  });

  test('save replaces map, remove persists and write errors propagate',
      () async {
    prefs.values['unrelated'] = 'keep';
    final record = Record(id: 'a');
    storage.scooters = {'a': record};
    await storage.save();
    expect(prefs.saved, {'a': record.toJson()});
    await storage.remove('a');
    expect(prefs.saved, isEmpty);
    expect(prefs.values['unrelated'], 'keep');
    prefs.failWrites = true;
    await expectLater(storage.save(), throwsStateError);
    await expectLater(storage.add('failed'), throwsStateError);
    expect(storage.scooters.keys, ['failed']);
  });

  test('IDs load lazily and filter without changing singleton autoConnect',
      () async {
    expect(await storage.getIds(), isEmpty);
    expect(prefs.reads, 0);
    prefs.values['savedScooters'] = '{"a":{"connect":false}}';
    expect(await storage.getIds(onlyAutoConnect: true), ['a']);
    final record = storage.scooters['a']!;
    expect(record.autoConnect, isFalse);
    expect(record.autoConnectWrites, 1);
    prefs.values['savedScooters'] = '{"changed":{}}';
    expect(await storage.getIds(), ['a']);
    expect(prefs.reads, 1);
    storage.scooters['b'] = Record(id: 'b');
    expect(await storage.getIds(onlyAutoConnect: true), ['b']);
    final filtered = storage.filterAutoConnect(storage.scooters);
    expect(filtered['b'], same(storage.scooters['b']));
    filtered.clear();
    expect(storage.scooters, hasLength(2));
  });

  test('recent selection invokes singleton setter and preserves insertion ties',
      () {
    expect(storage.getMostRecent(), isNull);
    final first = Record(id: 'first')..autoConnect = false;
    storage.scooters = {'first': first};
    expect(storage.getMostRecent(), same(first));
    expect(first.autoConnectWrites, 2);
    expect(storage.getMostRecent(), same(first));
    expect(first.autoConnectWrites, 2);
    storage.scooters['tied'] = Record(id: 'tied');
    storage.scooters['disabled'] =
        Record(id: 'disabled', lastPing: DateTime.now())..autoConnect = false;
    expect(storage.getMostRecent(), same(first));
    first.autoConnect = false;
    storage.scooters['tied']!.autoConnect = false;
    expect(storage.getMostRecent(), isNull);
    expect(prefs.writes, 0);
  });

  test('updatePing mutates only existing record without storage-level write',
      () {
    storage.updatePing('missing');
    expect(storage.scooters, isEmpty);
    final record = Record(id: 'a');
    storage.scooters['a'] = record;
    final before = DateTime.now();
    storage.updatePing('a');
    expect(record.lastPing.isBefore(before), isFalse);
    expect(prefs.writes, 0);
  });
}
