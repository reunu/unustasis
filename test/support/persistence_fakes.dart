import 'dart:convert';

import 'package:flutter_background_service_platform_interface/flutter_background_service_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Shared by the storage tests. No platform channels, BLE or service startup.
final class MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final Map<String, String> values = {};
  int writes = 0;
  int reads = 0;

  Map<String, dynamic> get saved => jsonDecode(values['savedScooters'] ?? '{}') as Map<String, dynamic>;

  void seed(Map<String, dynamic> scooters) {
    values['savedScooters'] = jsonEncode(scooters);
  }

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async =>
      values.keys.where((key) => parameters.filter.allowList?.contains(key) ?? true).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected preferences call: ${invocation.memberName}');
}

class RecordingBackgroundService extends FlutterBackgroundServicePlatform {
  final List<Map<String, dynamic>> updates = [];

  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    updates.add({'method': method, 'args': args});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected service actuation: ${invocation.memberName}');
}

// Setters return void while persisting asynchronously. The fake completes all
// work in microtasks, so an event-loop turn drains those writes before asserting.
Future<void> drainPreferenceWrites() => Future<void>.delayed(Duration.zero);
