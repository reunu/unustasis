import 'package:scooter_core/trip_expunge.dart';
import 'package:test/test.dart';

void main() {
  group('TripExpunge', () {
    const validBoundaryCorpus = [
      'never',
      'age:1ns',
      'age:1us',
      'age:1.5ms',
      'age:1h30m',
      'age:1d',
      'age:106751d',
      'count:0',
      'count:9223372036854775807',
      'size:0',
      'size:9223372036854775807',
    ];
    const invalidBoundaryCorpus = [
      'age:0',
      'age:0ns',
      'age:0.5ns',
      'age:.5us',
      'age:1.s',
      'age:1µs',
      'age:1μs',
      'age:106752d',
      'age:2562047h47m16.854775808s',
      'count:01',
      'count:+1',
      'count:9223372036854775808',
      'size:-1',
      'size:9223372036854775808',
      ' age:1ns',
      'age:1ns ',
      'age:1 ns',
      'count: 1',
      'size:1\t',
    ];

    test('accepts the trip.expunge valid boundary corpus', () {
      for (final value in validBoundaryCorpus) {
        expect(TripExpunge.parse(value).wireValue, value, reason: value);
      }
    });

    test('rejects the trip.expunge invalid boundary corpus', () {
      for (final value in invalidBoundaryCorpus) {
        expect(() => TripExpunge.parse(value), throwsFormatException,
            reason: value);
      }
    });

    test('rejects noncanonical and malformed age components', () {
      for (final value in [
        'age:00.5s',
        'age:01s',
        'age:01d',
        'age:0d',
        'age:1d1h',
        'age:1h1d',
        'age:1htrailing',
        'age:-1h',
        'age:+1h',
        'age:1h-1m',
        'age:9223372036854775808ns',
      ]) {
        expect(() => TripExpunge.parse(value), throwsFormatException,
            reason: value);
      }
    });

    test('constructs canonical int64 count and size values only', () {
      expect(TripExpunge(TripExpungePolicy.count, '0').wireValue, 'count:0');
      expect(TripExpunge(TripExpungePolicy.size, '42').wireValue, 'size:42');
      expect(() => TripExpunge(TripExpungePolicy.count, '00'),
          throwsFormatException);
      expect(() => TripExpunge(TripExpungePolicy.size, ' 42'),
          throwsFormatException);
    });
  });
}
