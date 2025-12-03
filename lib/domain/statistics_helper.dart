import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scooter_service.dart';

enum EventType { lock, unlock, openSeat, unknown }

enum EventSource { app, background, auto, unknown }

class LogEntry {
  final String timestamp;
  final EventType eventType;
  final EventSource source;
  final String scooterId;
  final LatLng? location;

  LogEntry({
    required this.timestamp,
    required this.eventType,
    required this.source,
    required this.scooterId,
    this.location,
  });

  @override
  String toString() {
    return 'LogEntry at $timestamp: ${eventType.toString()} from ${source.toString()} for scooter $scooterId at location $location';
  }

  String toJsonString() {
    return '{"timestamp": "$timestamp", "eventType": "${eventType.toString()}", "source": "${source.toString()}", "scooterId": "$scooterId", "location": "${location.toString()}"}';
  }

  factory LogEntry.fromJsonString(String jsonString) {
    Map<String, dynamic> json = jsonDecode(jsonString);
    return LogEntry(
      timestamp: json['timestamp'],
      eventType: EventType.values.firstWhere((e) => e.toString() == json['eventType'], orElse: () => EventType.unknown),
      source: EventSource.values.firstWhere((e) => e.toString() == json['source'], orElse: () => EventSource.unknown),
      scooterId: json['scooterId'],
      location: json['location'] != null ? LatLng.fromJson(json['location']) : null,
    );
  }
}

class StatisticsHelper {
  // Private constructor
  StatisticsHelper._internal();

  // Singleton instance
  static final StatisticsHelper _instance = StatisticsHelper._internal();

  // Factory constructor to return the same instance
  factory StatisticsHelper() {
    return _instance;
  }

  SharedPreferencesAsync prefs = SharedPreferencesAsync();

  void logEvent({
    required EventType eventType,
    String scooterId = "unknown",
    EventSource? source,
    DateTime? timestamp,
    LatLng? location,
  }) async {
    // inferring optional parameters
    timestamp ??= DateTime.now();
    source ??= identifyEventSource(eventType);
    List<String> logs = await prefs.getStringList("eventLogs") ?? [];
    LogEntry entry = LogEntry(
      timestamp: timestamp.toIso8601String(),
      eventType: eventType,
      source: source,
      scooterId: scooterId,
      location: location,
    );
    logs.add(entry.toJsonString());
    prefs.setStringList("eventLogs", logs);
  }

  Future<List<LogEntry>> getEventLogs() async {
    List<String> logs = await prefs.getStringList("eventLogs") ?? [];
    return logs.map((log) => LogEntry.fromJsonString(log)).toList();
  }

  // for debugging only
  void printEventLogs() async {
    List<LogEntry> logs = await getEventLogs();
    for (var log in logs) {
      print(log.toString());
    }
  }

  EventSource identifyEventSource(EventType type) {
    StackTrace stackTrace = StackTrace.current;
    String stackTraceString = stackTrace.toString();
    if (stackTraceString.contains('rssiTimer') || type == EventType.openSeat && stackTraceString.contains('unlock')) {
      return EventSource.auto;
    } else if (stackTraceString.contains('bg_service')) {
      return EventSource.background;
    } else {
      return EventSource.app;
    }
  }
}
