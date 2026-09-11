import 'dart:convert';

import 'package:scooter_core/characteristic_values.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCharacteristicString', () {
    test('decodes UTF-8, removes every NUL and trims surrounding whitespace',
        () {
      expect(
        decodeCharacteristicString([
          0,
          ...utf8.encode(' \tGrü'),
          0,
          ...utf8.encode('ße 🛵\r\n'),
          0,
        ]),
        'Grüße 🛵',
      );
    });

    test('preserves internal whitespace', () {
      expect(decodeCharacteristicString(utf8.encode(' a  b\tc ')), 'a  b\tc');
    });

    test('accepts empty, NUL-only and whitespace-only values', () {
      for (final bytes in <List<int>>[
        [],
        [0, 0],
        [32, 9, 10, 0]
      ]) {
        expect(decodeCharacteristicString(bytes), isEmpty);
      }
    });

    test('replaces malformed UTF-8 instead of throwing', () {
      expect(decodeCharacteristicString([0xff, 65, 0xc3]), '\uFFFDA\uFFFD');
    });
  });

  group('decodeUint32', () {
    test('decodes exactly four little-endian bytes', () {
      expect(decodeUint32([0, 0, 0, 0]), 0);
      expect(decodeUint32([0x78, 0x56, 0x34, 0x12]), 0x12345678);
    });

    test('preserves the unsigned high bit and maximum value', () {
      expect(decodeUint32([0, 0, 0, 0x80]), 2147483648);
      expect(decodeUint32([0xff, 0xff, 0xff, 0xff]), 4294967295);
    });

    test('rejects both truncated and padded values', () {
      for (final length in [0, 1, 2, 3, 5, 6, 8]) {
        expect(decodeUint32(List.filled(length, 0)), isNull,
            reason: 'length $length');
      }
    });
  });

  group('parseOdometerMeters', () {
    test('rejects values shorter than four bytes', () {
      for (var length = 0; length < 4; length++) {
        expect(parseOdometerMeters(List.filled(length, 0)), isNull);
      }
    });

    test('accepts four bytes and ignores trailing padding without mutation',
        () {
      final bytes = [0x78, 0x56, 0x34, 0x12, 0xff, 0xaa];
      expect(parseOdometerMeters(bytes.sublist(0, 4)), 0x12345678);
      expect(parseOdometerMeters(bytes), 0x12345678);
      expect(bytes, [0x78, 0x56, 0x34, 0x12, 0xff, 0xaa]);
    });

    test('preserves unsigned high-bit values even with padding', () {
      expect(parseOdometerMeters([0, 0, 0, 0x80, 0]), 2147483648);
      expect(parseOdometerMeters([255, 255, 255, 255, 0]), 4294967295);
    });
  });
}
