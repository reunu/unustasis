import 'dart:convert';

/// Largest complete trip response accepted from the BLE transport.
const int tripCounterResponseMaxBytes = 480;
const int _maxInt64 = 9223372036854775807;
const int _maxDateTimeSeconds = 8640000000000;
final RegExp _canonicalNonNegativeInt64 = RegExp(r'(?:0|[1-9][0-9]*)');

enum TripResetPolicy { ride, day, battery, manual }

extension TripResetPolicyWire on TripResetPolicy {
  String get wireName => name;

  static TripResetPolicy? parse(String value) {
    for (final policy in TripResetPolicy.values) {
      if (policy.wireName == value) return policy;
    }
    return null;
  }
}

enum TripResetReason { initial, ride, day, battery, manual }

extension TripResetReasonWire on TripResetReason {
  static TripResetReason? parse(String value) {
    for (final reason in TripResetReason.values) {
      if (reason.name == value) return reason;
    }
    return null;
  }
}

enum TripCounterStatus { idle, recording }

extension TripCounterStatusWire on TripCounterStatus {
  static TripCounterStatus? parse(String value) {
    for (final status in TripCounterStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// A nonzero scooter timestamp that may exceed Dart's [DateTime] range.
class TripTimestamp {
  const TripTimestamp(this.seconds);

  final int seconds;

  /// The timestamp when it can be represented without clamping or overflow.
  DateTime? get dateTime => seconds <= _maxDateTimeSeconds
      ? DateTime.fromMillisecondsSinceEpoch(
          seconds * Duration.millisecondsPerSecond,
          isUtc: true,
        )
      : null;
}

/// A complete aggregate-only `trip:data` response from the scooter.
class TripCounterSnapshot {
  const TripCounterSnapshot({
    required this.distanceMeters,
    required this.ridingSeconds,
    required this.averageSpeedKph,
    required this.resetPolicy,
    required this.lastReset,
    required this.lastResetReason,
    required this.generation,
    required this.status,
  });

  final int distanceMeters;
  final int ridingSeconds;
  final int averageSpeedKph;
  final TripResetPolicy resetPolicy;
  final TripTimestamp? lastReset;
  final TripResetReason lastResetReason;

  /// Scooter-side aggregate revision. It is not presented to users.
  final int generation;
  final TripCounterStatus status;

  static TripCounterSnapshot parse(String response) {
    if (utf8.encode(response).length > tripCounterResponseMaxBytes) {
      throw const FormatException('Trip data exceeds the response limit');
    }
    const prefix = 'trip:data:';
    if (!response.startsWith(prefix)) {
      throw const FormatException('Expected a trip:data response');
    }
    final parts = response.substring(prefix.length).split(':');
    if (parts.length.isOdd || parts.isEmpty) {
      throw const FormatException('Trip data has unpaired fields');
    }
    const fields = {
      'distance-m',
      'duration-s',
      'average-speed-kmh',
      'reset-policy',
      'reset-at',
      'reset-reason',
      'generation',
      'status',
    };
    final values = <String, String>{};
    for (var index = 0; index < parts.length; index += 2) {
      final key = parts[index];
      final value = parts[index + 1];
      if (!fields.contains(key) || value.isEmpty || values.containsKey(key)) {
        throw const FormatException('Trip data has invalid fields');
      }
      values[key] = value;
    }
    if (values.length != fields.length || !fields.containsAll(values.keys)) {
      throw const FormatException('Trip data is incomplete');
    }
    int parseNonNegativeInt64(String key) {
      final value = values[key]!;
      final match = _canonicalNonNegativeInt64.matchAsPrefix(value);
      if (match == null ||
          match.end != value.length ||
          value.length > _maxInt64.toString().length ||
          value.length == _maxInt64.toString().length &&
              value.compareTo(_maxInt64.toString()) > 0) {
        throw FormatException('Trip data has invalid $key');
      }
      return int.parse(value);
    }

    final policy = TripResetPolicyWire.parse(values['reset-policy']!);
    final reason = TripResetReasonWire.parse(values['reset-reason']!);
    final status = TripCounterStatusWire.parse(values['status']!);
    if (policy == null || reason == null || status == null) {
      throw const FormatException('Trip data has an unknown enum value');
    }
    final resetAt = parseNonNegativeInt64('reset-at');
    return TripCounterSnapshot(
      distanceMeters: parseNonNegativeInt64('distance-m'),
      ridingSeconds: parseNonNegativeInt64('duration-s'),
      averageSpeedKph: parseNonNegativeInt64('average-speed-kmh'),
      resetPolicy: policy,
      lastReset: resetAt == 0 ? null : TripTimestamp(resetAt),
      lastResetReason: reason,
      generation: parseNonNegativeInt64('generation'),
      status: status,
    );
  }
}
