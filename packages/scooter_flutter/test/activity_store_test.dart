import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scooter_flutter/activity_store.dart';

// ignore: must_be_immutable
class Preferences extends Fake implements SharedPreferencesAsync {
  bool? enabled;
  final logs = <String>[];
  Completer<void>? gate;
  Object? failure;
  final keys = <String>[];
  @override
  Future<bool?> getBool(String key) async {
    keys.add(key);
    return enabled;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    keys.add(key);
    enabled = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    keys.add(key);
    return logs.toList();
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    keys.add(key);
    await gate?.future;
    if (failure != null) throw failure!;
    logs
      ..clear()
      ..addAll(value);
  }

  @override
  Future<void> remove(String key) async {
    keys.add(key);
    logs.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ActivityStore accepts preferences at construction; no plugin registration.
  late Preferences prefs;
  late ActivityStore store;
  late List<Object> errors;
  int checks = 0, locations = 0;
  setUp(() {
    prefs = Preferences();
    errors = [];
    checks = 0;
    locations = 0;
    store = ActivityStore(
        preferences: prefs,
        checkLocationPermission: () async {
          checks++;
          return true;
        },
        readLocation: () async {
          locations++;
          return const LatLng(1, 2);
        },
        locationFailed: errors.add);
  });
  test(
      'independent shared store owns defaults enabled key queue and supplied location acquisition',
      () async {
    expect(await store.isEventLoggingEnabled(), isTrue);
    await store.logEvent(eventType: EventType.lock, scooterId: 'A');
    await store.logEvent(eventType: EventType.unlock, scooterId: 'B');
    await store.pendingWrites;
    expect(checks, 1);
    expect(locations, 2);
    expect((await store.getEventLogs()).map((e) => e.scooterId), ['A', 'B']);
    expect((await store.getEventLogs()).first.location, const LatLng(1, 2));
    await store.setEventLoggingEnabled(false);
    await store.logEvent(eventType: EventType.openSeat);
    await store.pendingWrites;
    expect(prefs.logs, hasLength(2));
    expect(locations, 2);
    expect(prefs.keys.toSet(), {'eventLogs', 'eventLoggingEnabled'});
  });
  test('completion is enqueue-only and clear remains outside FIFO', () async {
    prefs.gate = Completer<void>();
    await store.logEvent(eventType: EventType.lock);
    expect(prefs.logs, isEmpty);
    await store.clearEventLogs();
    prefs.gate!.complete();
    await store.pendingWrites;
    expect(prefs.logs, hasLength(1));
  });
  test('write failures poison the queue even if caller observes pendingWrites',
      () async {
    prefs.failure = StateError('disk');
    final first = store.logEvent(eventType: EventType.lock);
    await expectLater(store.pendingWrites, throwsStateError);
    await first;
    prefs.failure = null;
    final next = store.logEvent(eventType: EventType.unlock);
    await expectLater(store.pendingWrites, throwsStateError);
    await next;
    expect(prefs.logs, isEmpty);
    expect(locations, 1);
  });
  test(
      'permission failures poison queue; location acquisition failures alone are caught',
      () async {
    store = ActivityStore(
        preferences: prefs,
        checkLocationPermission: () async => throw StateError('permission'),
        readLocation: () async => const LatLng(1, 2),
        locationFailed: errors.add);
    store.logEvent(eventType: EventType.lock);
    await expectLater(store.pendingWrites, throwsStateError);
    expect(errors, isEmpty);
    expect(prefs.logs, isEmpty);
    store = ActivityStore(
        preferences: prefs,
        checkLocationPermission: () async => true,
        readLocation: () async => throw StateError('location'),
        locationFailed: errors.add);
    await store.logEvent(eventType: EventType.lock);
    await store.pendingWrites;
    expect(errors, hasLength(1));
    expect((await store.getEventLogs()).single.location, isNull);
  });
  test(
      'each store has its own queue and cached permission; no singleton imposed by shared runtime',
      () async {
    prefs.gate = Completer<void>();
    await store.logEvent(eventType: EventType.lock);
    final otherPrefs = Preferences();
    final other = ActivityStore(
        preferences: otherPrefs,
        checkLocationPermission: () async => false,
        readLocation: () async => throw StateError('must not acquire'),
        locationFailed: errors.add);
    await other.logEvent(eventType: EventType.unlock);
    await other.pendingWrites;
    expect(otherPrefs.logs, hasLength(1));
    expect(prefs.logs, isEmpty);
    prefs.gate!.complete();
    await store.pendingWrites;
    expect(store.locationPermission, isTrue);
    expect(other.locationPermission, isFalse);
  });
}
