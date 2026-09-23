import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/src/storage/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryPreferences extends Fake implements SharedPreferencesAsync {
  final Map<String, Object> values = {};
  final List<String> reads = [];
  final List<String> writes = [];
  final Completer<void>? writeGate;
  final bool failWrites;

  MemoryPreferences({this.writeGate, this.failWrites = false});

  @override
  Future<bool?> getBool(String key) async {
    reads.add(key);
    return values[key] as bool?;
  }

  @override
  Future<int?> getInt(String key) async {
    reads.add(key);
    return values[key] as int?;
  }

  Future<void> _write(String key, Object value) async {
    writes.add(key);
    if (writeGate != null) await writeGate!.future;
    if (failWrites) throw StateError('persistence failed');
    values[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) => _write(key, value);

  @override
  Future<void> setInt(String key, int value) => _write(key, value);
}

void main() {
  test('construction does no IO and retains pre-restore defaults', () {
    final prefs = MemoryPreferences();
    final updates = <Map<String, dynamic>>[];
    final settings = UserSettings(preferences: prefs, onUpdate: updates.add);
    expect(settings.autoUnlockThreshold, -65);
    expect(settings.optionalAuth, isFalse);
    expect(settings.warnOfUnlockedHandlebars, isTrue);
    expect(settings.legacyAutoUnlock, isFalse);
    expect(settings.legacyOpenSeatOnUnlock, isFalse);
    expect(settings.legacyHazardLocking, isFalse);
    expect(prefs.reads, isEmpty);
    expect(prefs.writes, isEmpty);
    expect(updates, isEmpty);
  });

  test('restore uses defaults and reads in legacy order without updates',
      () async {
    final prefs = MemoryPreferences();
    final updates = <Map<String, dynamic>>[];
    final settings = UserSettings(preferences: prefs, onUpdate: updates.add)
      ..autoUnlockThreshold = -99
      ..warnOfUnlockedHandlebars = false;
    await settings.restore();
    expect(settings.autoUnlockThreshold, -65);
    expect(settings.optionalAuth, isTrue);
    expect(settings.warnOfUnlockedHandlebars, isTrue);
    expect(settings.legacyAutoUnlock, isFalse);
    expect(prefs.reads, [
      'autoUnlockThreshold',
      'biometrics',
      'autoUnlock',
      'openSeatOnUnlock',
      'hazardLocking',
      'unlockedHandlebarsWarning',
    ]);
    expect(prefs.writes, isEmpty);
    expect(updates, isEmpty);
  });

  test('restore restores the global fields and the legacy keyless flags',
      () async {
    final prefs = MemoryPreferences()
      ..values.addAll({
        'autoUnlock': true,
        'autoUnlockThreshold': -99,
        'biometrics': true,
        'openSeatOnUnlock': true,
        'hazardLocking': true,
        'unlockedHandlebarsWarning': false,
      });
    final settings = UserSettings(preferences: prefs);
    await settings.restore();
    expect(settings.autoUnlockThreshold, -99);
    expect(settings.optionalAuth, isFalse);
    expect(settings.warnOfUnlockedHandlebars, isFalse);
    expect(settings.legacyAutoUnlock, isTrue);
    expect(settings.legacyOpenSeatOnUnlock, isTrue);
    expect(settings.legacyHazardLocking, isTrue);
    prefs.values['biometrics'] = false;
    await settings.restore();
    expect(settings.optionalAuth, isTrue);
  });

  test('the legacy keyless keys are only ever read', () async {
    final prefs = MemoryPreferences()..values.addAll({'autoUnlock': true});
    final settings = UserSettings(preferences: prefs);
    await settings.restore();
    await settings.setAutoUnlockThreshold(-99);
    expect(prefs.writes, ['autoUnlockThreshold']);
  });

  final setters = <String, Future<void> Function(UserSettings)>{
    'autoUnlockThreshold': (settings) => settings.setAutoUnlockThreshold(-99),
  };
  Object field(UserSettings settings, String key) => switch (key) {
        'autoUnlockThreshold' => settings.autoUnlockThreshold,
        _ => throw StateError(key),
      };

  for (final entry in setters.entries) {
    final key = entry.key;
    final value = key == 'autoUnlockThreshold' ? -99 : true;
    test('$key mutates before write, then callbacks after persistence',
        () async {
      final prefs = MemoryPreferences(writeGate: Completer<void>());
      final updates = <Map<String, dynamic>>[];
      final settings = UserSettings(
          preferences: prefs,
          onUpdate: (data) {
            expect(prefs.values[key], value);
            updates.add(data);
          });
      final pending = entry.value(settings);
      expect(field(settings, key), value);
      expect(prefs.writes, [key]);
      expect(prefs.values, isEmpty);
      expect(updates, isEmpty);
      prefs.writeGate!.complete();
      await pending;
      expect(updates, [
        {key: value}
      ]);
    });

    test('$key keeps mutation but does not callback after failed write',
        () async {
      final prefs = MemoryPreferences(failWrites: true);
      final updates = <Map<String, dynamic>>[];
      final settings = UserSettings(preferences: prefs, onUpdate: updates.add);
      await expectLater(entry.value(settings), throwsStateError);
      expect(field(settings, key), value);
      expect(prefs.values, isEmpty);
      expect(updates, isEmpty);
    });

    test('$key persists without callback', () async {
      final prefs = MemoryPreferences();
      final settings = UserSettings(preferences: prefs, onUpdate: null);
      await entry.value(settings);
      expect(prefs.values, {key: value});
    });
  }
}
