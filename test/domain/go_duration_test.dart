import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/go_duration.dart';

void main() {
  group('tryParseGoDuration', () {
    test('parses single-unit durations', () {
      expect(tryParseGoDuration("8h"), const Duration(hours: 8));
      expect(tryParseGoDuration("30m"), const Duration(minutes: 30));
      expect(tryParseGoDuration("28800s"), const Duration(seconds: 28800));
      expect(tryParseGoDuration("500ms"), const Duration(milliseconds: 500));
    });

    test('parses multi-segment durations', () {
      expect(tryParseGoDuration("1h30m"), const Duration(hours: 1, minutes: 30));
      expect(tryParseGoDuration("8h0m0s"), const Duration(hours: 8));
      expect(tryParseGoDuration("168h0m0s"), const Duration(days: 7));
    });

    test('parses fractional values', () {
      expect(tryParseGoDuration("1.5h"), const Duration(minutes: 90));
      expect(tryParseGoDuration("0.5s"), const Duration(milliseconds: 500));
    });

    test('accepts bare zero', () {
      expect(tryParseGoDuration("0"), Duration.zero);
      expect(tryParseGoDuration("0s"), Duration.zero);
    });

    test('rejects invalid input', () {
      expect(tryParseGoDuration(""), isNull);
      expect(tryParseGoDuration("8"), isNull); // missing unit
      expect(tryParseGoDuration("8 h"), isNull);
      expect(tryParseGoDuration("h8"), isNull);
      expect(tryParseGoDuration("-1h"), isNull);
      expect(tryParseGoDuration("+1h"), isNull);
      expect(tryParseGoDuration("8hx"), isNull);
      expect(tryParseGoDuration("8d"), isNull); // Go has no day unit
    });
  });

  group('formatGoDuration', () {
    test('formats as whole seconds', () {
      expect(formatGoDuration(const Duration(hours: 8)), "28800s");
      expect(formatGoDuration(const Duration(days: 1)), "86400s");
      expect(formatGoDuration(Duration.zero), "0s");
    });

    test('round-trips through the parser', () {
      const original = Duration(days: 3, hours: 5);
      expect(tryParseGoDuration(formatGoDuration(original)), original);
    });
  });
}
