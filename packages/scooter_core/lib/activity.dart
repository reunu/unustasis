import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'actions.dart';
export 'actions.dart' show EventType, EventSource;
export 'package:latlong2/latlong.dart' show LatLng;

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
    Map<String, dynamic> json = jsonDecode(jsonString) as Map<String, dynamic>;
    final Map<String, dynamic>? locJson =
        json['location'] as Map<String, dynamic>?;
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      eventType: EventType.values.firstWhere(
          (e) => e.toString() == json['eventType'],
          orElse: () => EventType.unknown),
      source: EventSource.values.firstWhere(
          (e) => e.toString() == json['source'],
          orElse: () => EventSource.unknown),
      scooterId: json['scooterId'] as String,
      soc1: json['soc1'] as int?,
      soc2: json['soc2'] as int?,
      location: locJson != null ? LatLng.fromJson(locJson) : null,
    );
  }
}
