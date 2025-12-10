import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EventType { lock, unlock, openSeat, hibernate, wakeUp, unknown }

enum EventSource { app, background, auto, unknown }

class LogEntry {
  final DateTime timestamp;
  final EventType eventType;
  final EventSource source;
  final String scooterId;
  final LatLng? location;
  final int? soc1;
  final int? soc2;

  LogEntry({
    required this.timestamp,
    required this.eventType,
    required this.source,
    required this.scooterId,
    this.soc1,
    this.soc2,
    this.location,
  });

  @override
  String toString() {
    return 'LogEntry at $timestamp: ${eventType.toString()} from ${source.toString()} for scooter $scooterId at location $location';
  }

  String toJsonString() {
    return jsonEncode({
      'timestamp': timestamp.toIso8601String(),
      'eventType': eventType.toString(),
      'source': source.toString(),
      'scooterId': scooterId,
      'soc1': soc1,
      'soc2': soc2,
      'location': location?.toJson()
    });
  }

  factory LogEntry.fromJsonString(String jsonString) {
    Map<String, dynamic> json = jsonDecode(jsonString);
    final Map<String, dynamic>? locJson = json['location'];
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      eventType: EventType.values.firstWhere((e) => e.toString() == json['eventType'], orElse: () => EventType.unknown),
      source: EventSource.values.firstWhere((e) => e.toString() == json['source'], orElse: () => EventSource.unknown),
      scooterId: json['scooterId'],
      soc1: json['soc1'],
      soc2: json['soc2'],
      location: locJson != null ? LatLng.fromJson(locJson) : null,
    );
  }
}

class StatisticsHelper {
  Logger log = Logger("StatisticsHelper");

  // Private constructor
  StatisticsHelper._internal();

  // Singleton instance
  static final StatisticsHelper _instance = StatisticsHelper._internal();

  // Factory constructor to return the same instance
  factory StatisticsHelper() {
    return _instance;
  }

  SharedPreferencesAsync prefs = SharedPreferencesAsync();
  bool? locationPermission;
  Geolocator geolocator = Geolocator();

  // Queue to serialize writes to SharedPreferences and avoid race conditions
  Future<void> _writeQueue = Future.value();

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
      if (locationPermission == null) {
        final permission = await Geolocator.checkPermission();
        locationPermission = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
      }
      if (locationPermission == true && location == null) {
        try {
          Position position = await Geolocator.getCurrentPosition();
          location = LatLng(position.latitude, position.longitude);
        } catch (e) {
          log.warning("Couldn't add location to logged event: $e");
        }
      }
      // inferring optional parameters
      List<String> logs = await prefs.getStringList("eventLogs") ?? [];
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
      await prefs.setStringList("eventLogs", logs);
    });
  }

  Future<List<LogEntry>> getEventLogs() async {
    List<String> logs = await prefs.getStringList("eventLogs") ?? [];
    return logs.map((log) => LogEntry.fromJsonString(log)).toList();
  }

  // for debugging only
  Future<void> printEventLogs() async {
    List<String> logs = await prefs.getStringList("eventLogs") ?? [];
    for (var log in logs) {
      LogEntry entry = LogEntry.fromJsonString(log);
      debugPrint(entry.toString());
    }
  }

  Future<void> clearEventLogs() async {
    await prefs.remove("eventLogs");
  }

  Future<void> addDemoLogs() async {
    await _writeQueue; // ensure previous writes are flushed
    logEvent(
      eventType: EventType.lock,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.app,
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      soc1: 80,
      soc2: 78,
      location: LatLng(40.7128, -74.0060),
    );
    logEvent(
      eventType: EventType.unlock,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.auto,
      timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 30)),
      soc1: 79,
      soc2: 77,
      location: LatLng(40.7138, -74.0050),
    );
    logEvent(
      eventType: EventType.openSeat,
      scooterId: "CA:6F:46:FD:EF:DC",
      source: EventSource.background,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      soc1: 78,
      soc2: 76,
      location: LatLng(40.7148, -74.0040),
    );
    logEvent(
      eventType: EventType.lock,
      scooterId: "F1:99:B2:59:94:21",
      source: EventSource.app,
      timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
      soc1: 85,
      soc2: 100,
      location: LatLng(40.7158, -74.0030),
    );
    await _writeQueue; // wait until all demo logs are written
  }
}
