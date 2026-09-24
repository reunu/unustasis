import 'dart:convert';

import 'package:scooter_core/trip_counter.dart';
import 'package:test/test.dart';

const zero = 'trip:data:distance-m:0:duration-s:0:average-speed-kmh:0:'
    'reset-policy:manual:reset-at:0:reset-reason:initial:generation:0:status:idle';
const maxInt64 = '9223372036854775807';

String _withValue(String response, String field, String value) =>
    response.replaceFirst('$field:0', '$field:$value');

void main() {
  test('parses the initial aggregate trip response including zero values', () {
    final snapshot = TripCounterSnapshot.parse(zero);
    expect(snapshot.distanceMeters, 0);
    expect(snapshot.ridingSeconds, 0);
    expect(snapshot.averageSpeedKph, 0);
    expect(snapshot.resetPolicy, TripResetPolicy.manual);
    expect(snapshot.lastReset, isNull);
    expect(snapshot.lastResetReason, TripResetReason.initial);
    expect(snapshot.status, TripCounterStatus.idle);
  });

  test('parses canonical max-int64 fields without overflowing timestamps', () {
    var response = zero;
    for (final field in [
      'distance-m',
      'duration-s',
      'average-speed-kmh',
      'reset-at',
      'generation',
    ]) {
      response = _withValue(response, field, maxInt64);
    }

    final snapshot = TripCounterSnapshot.parse(response);
    expect(snapshot.distanceMeters, 9223372036854775807);
    expect(snapshot.ridingSeconds, 9223372036854775807);
    expect(snapshot.averageSpeedKph, 9223372036854775807);
    expect(snapshot.generation, 9223372036854775807);
    expect(snapshot.lastReset!.seconds, 9223372036854775807);
    expect(snapshot.lastReset!.dateTime, isNull);
  });

  test('requires every known pair exactly once', () {
    expect(() => TripCounterSnapshot.parse('trip:data:distance-m:1'),
        throwsFormatException);
    expect(() => TripCounterSnapshot.parse('$zero:distance-m:1'),
        throwsFormatException);
    expect(() => TripCounterSnapshot.parse('$zero:profile-id:secret'),
        throwsFormatException);
    expect(
        () => TripCounterSnapshot.parse('$zero:broken'), throwsFormatException);
  });

  test('rejects noncanonical and overflowing int64 fields', () {
    for (final field in [
      'distance-m',
      'duration-s',
      'average-speed-kmh',
      'reset-at',
      'generation',
    ]) {
      for (final value in ['-1', '+1', '01', '9223372036854775808']) {
        expect(() => TripCounterSnapshot.parse(_withValue(zero, field, value)),
            throwsFormatException,
            reason: '$field:$value');
      }
    }
  });

  test('accepts the 480-byte transport limit before field validation', () {
    final valueLength = tripCounterResponseMaxBytes - zero.length + 1;
    final response = _withValue(zero, 'distance-m', '0' * valueLength);
    expect(utf8.encode(response).length, tripCounterResponseMaxBytes);

    try {
      TripCounterSnapshot.parse(response);
      fail('Expected a noncanonical integer failure');
    } on FormatException catch (error) {
      expect(error.message, isNot('Trip data exceeds the response limit'));
    }
  });

  test('rejects a 481-byte transport response', () {
    final valueLength = tripCounterResponseMaxBytes - zero.length + 2;
    final response = _withValue(zero, 'distance-m', '0' * valueLength);
    expect(utf8.encode(response).length, tripCounterResponseMaxBytes + 1);
    expect(
      () => TripCounterSnapshot.parse(response),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        'Trip data exceeds the response limit',
      )),
    );
  });

  test('rejects malformed values', () {
    expect(
      () => TripCounterSnapshot.parse(
          zero.replaceFirst('reset-reason:initial', 'reset-reason:unknown')),
      throwsFormatException,
    );
  });
}
