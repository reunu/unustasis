import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import '../support/persistence_fakes.dart';
import 'package:unustasis/domain/statistics_helper.dart';

// Mutable fake intentionally models pending persistence.
// ignore: must_be_immutable
class _Preferences extends Fake implements SharedPreferencesAsync {
  final accesses = <String>[];
  List<String> logs = [];
  bool? legacyEnabled;
  Completer<void>? writeGate;
  @override
  Future<bool?> getBool(String key) async {
    accesses.add(key);
    return legacyEnabled;
  }
  @override
  Future<void> setBool(String key, bool value) async => accesses.add(key);
  @override
  Future<List<String>?> getStringList(String key) async => logs.toList();
  @override
  Future<void> setStringList(String key, List<String> value) async {
    await writeGate?.future;
    logs = value.toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferencesAsyncPlatform.instance = MemoryPreferences());
  for (final enabled in [null, false]) {
    test('U logs without accessing legacy eventLoggingEnabled=$enabled', () async {
      final prefs = _Preferences()..legacyEnabled = enabled;
      final helper = StatisticsHelper()..prefs = prefs..locationPermission = false;
      await helper.logEvent(eventType: EventType.lock);
      // Demo completion also drains prior work in the existing public API.
      await helper.addDemoLogs();
      expect(prefs.logs, hasLength(5));
      expect(prefs.accesses, isEmpty);
      final entries = await helper.getEventLogs();
      expect(entries.first.scooterId, 'unknown');
      expect(entries.first.source, EventSource.unknown);
      expect(entries.skip(1).map((e) => e.scooterId), [
        'CA:6F:46:FD:EF:DC', 'CA:6F:46:FD:EF:DC',
        'CA:6F:46:FD:EF:DC', 'F1:99:B2:59:94:21',
      ]);
      expect(entries.skip(1).map((e) => e.soc1), [80, 79, 78, 85]);
      expect(entries.last.location!.latitude, 40.7158);
    });
  }
  test('U logEvent completes on enqueue, not preference commit', () async {
    final gate = Completer<void>();
    final prefs = _Preferences()..writeGate = gate;
    final helper = StatisticsHelper()..prefs = prefs..locationPermission = false;
    await helper.logEvent(eventType: EventType.openSeat);
    expect(prefs.logs, isEmpty);
    gate.complete();
    await helper.addDemoLogs();
    expect(prefs.logs, hasLength(5));
  });
}
