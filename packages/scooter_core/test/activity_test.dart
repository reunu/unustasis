import 'dart:convert';
import 'package:test/test.dart';
import 'package:scooter_core/activity.dart';

void main() {
  test(
      'activity JSON remains the exact preference record including nulls and coordinate shape',
      () {
    final entry = LogEntry(
        timestamp: DateTime.utc(2024, 2, 3, 4, 5, 6),
        eventType: EventType.openSeat,
        source: EventSource.auto,
        scooterId: 'A',
        soc2: 50,
        location: const LatLng(1.25, -2.5));
    expect(
        entry.toJsonString(),
        jsonEncode({
          'timestamp': '2024-02-03T04:05:06.000Z',
          'eventType': 'EventType.openSeat',
          'source': 'EventSource.auto',
          'scooterId': 'A',
          'soc1': null,
          'soc2': 50,
          'location': const LatLng(1.25, -2.5).toJson(),
        }));
    expect(LogEntry.fromJsonString(entry.toJsonString()).toJsonString(),
        entry.toJsonString());
  });
  test(
      'legacy unknown enum fallback and malformed timestamp behavior are unchanged',
      () {
    final json = {
      'timestamp': '2024-02-03T04:05:06.000Z',
      'eventType': 'future',
      'source': 'future',
      'scooterId': 'A'
    };
    final entry = LogEntry.fromJsonString(jsonEncode(json));
    expect(entry.eventType, EventType.unknown);
    expect(entry.source, EventSource.unknown);
    expect(entry.location, isNull);
    expect(entry.soc1, isNull);
    expect(entry.soc2, isNull);
    json['timestamp'] = 'invalid';
    expect(
        () => LogEntry.fromJsonString(jsonEncode(json)), throwsFormatException);
  });
}
