import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scooter_core/activity.dart';
export 'package:scooter_core/activity.dart';

/// Activity persistence retains the legacy immediate enqueue completion, poisoned
/// failure chain and unqueued clear behavior. Platform location is supplied.
class ActivityStore {
  ActivityStore(
      {required this.checkLocationPermission,
      required this.readLocation,
      required this.locationFailed,
      SharedPreferencesAsync? preferences})
      : prefs = preferences ?? SharedPreferencesAsync();
  final Future<bool> Function() checkLocationPermission;
  final Future<LatLng?> Function() readLocation;
  final void Function(Object) locationFailed;
  Future<void> get pendingWrites => _writeQueue;

  SharedPreferencesAsync prefs;
  bool? locationPermission;

  static const String _eventLogsKey = "eventLogs";
  static const String _eventLoggingEnabledKey = "eventLoggingEnabled";

  // Queue to serialize writes to SharedPreferences and avoid race conditions
  Future<void> _writeQueue = Future.value();

  Future<bool> isEventLoggingEnabled() async {
    return await prefs.getBool(_eventLoggingEnabledKey) ?? true;
  }

  Future<void> setEventLoggingEnabled(bool enabled) async {
    await prefs.setBool(_eventLoggingEnabledKey, enabled);
  }

  Future<void> logEvent({
    required EventType eventType,
    String scooterId = "unknown",
    EventSource? source,
    DateTime? timestamp,
    int? soc1,
    int? soc2,
    LatLng? location,
  }) async {
    _writeQueue = _writeQueue.then((_) async {
      if (!await isEventLoggingEnabled()) return;
      locationPermission ??= await checkLocationPermission();
      if (locationPermission == true && location == null) {
        try {
          location = await readLocation();
        } catch (e) {
          locationFailed(e);
        }
      }
      // inferring optional parameters
      List<String> logs = await prefs.getStringList(_eventLogsKey) ?? [];
      LogEntry entry = LogEntry(
        timestamp: timestamp ?? DateTime.now(),
        eventType: eventType,
        source: source ?? EventSource.unknown,
        scooterId: scooterId,
        soc1: soc1,
        soc2: soc2,
        location: location,
      );
      logs.add(entry.toJsonString());
      await prefs.setStringList(_eventLogsKey, logs);
    });
  }

  Future<List<LogEntry>> getEventLogs() async {
    List<String> logs = await prefs.getStringList(_eventLogsKey) ?? [];
    return logs.map((log) => LogEntry.fromJsonString(log)).toList();
  }

  // for debugging only
  Future<void> printEventLogs() async {
    List<String> logs = await prefs.getStringList(_eventLogsKey) ?? [];
    for (var log in logs) {
      LogEntry entry = LogEntry.fromJsonString(log);
      debugPrint(entry.toString());
    }
  }

  Future<void> clearEventLogs() async {
    await prefs.remove(_eventLogsKey);
  }
}
