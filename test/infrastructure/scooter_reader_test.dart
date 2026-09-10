import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/infrastructure/scooter_reader.dart';

void main() {
  group('parseOdometerMeters', () {
    test('decodes a four-byte little-endian unsigned metre value', () {
      expect(parseOdometerMeters([0x78, 0x56, 0x34, 0x12]), 0x12345678);
    });

    test('accepts a padded payload', () {
      expect(parseOdometerMeters([0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0]), 0x12345678);
    });

    test('rejects payloads shorter than four bytes', () {
      expect(parseOdometerMeters([]), isNull);
      expect(parseOdometerMeters([1, 2, 3]), isNull);
    });
  });
}
