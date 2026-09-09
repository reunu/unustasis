import 'package:test/test.dart';
import 'package:scooter_core/alarm_wake_sources.dart';

void main() {
  group('AlarmWakeSources.fromBytes', () {
    test('unpacks the phase, mask and wake timer', () {
      // hibernating, motion + wake-timer + BLE, 3600s
      final sources = AlarmWakeSources.fromBytes([1, 0x0b, 0x10, 0x0e, 0x00, 0x00]);
      expect(sources, isNotNull);
      expect(sources!.hibernating, isTrue);
      expect(sources.motionWouldWake, isTrue);
      expect(sources.wakeTimerArmed, isTrue);
      expect(sources.brakeWouldWake, isFalse);
      expect(sources.bleWouldWake, isTrue);
      expect(sources.lowCbbWouldWake, isFalse);
      expect(sources.wakeTimerDuration, const Duration(hours: 1));
    });

    test('leaves the duration null when the timer is not armed', () {
      final sources = AlarmWakeSources.fromBytes([0, 0x01, 0x00, 0x00, 0x00, 0x00]);
      expect(sources, isNotNull);
      expect(sources!.hibernating, isFalse);
      expect(sources.wakeTimerArmed, isFalse);
      expect(sources.wakeTimerDuration, isNull);
    });

    test('reads the timer as little-endian across all four bytes', () {
      final sources = AlarmWakeSources.fromBytes([1, 0x02, 0x00, 0x00, 0x00, 0x01]);
      expect(sources!.wakeTimerDuration, const Duration(seconds: 0x01000000));
    });

    test('returns null on any other length', () {
      expect(AlarmWakeSources.fromBytes([]), isNull);
      expect(AlarmWakeSources.fromBytes([1, 0x01, 0, 0, 0]), isNull);
      expect(AlarmWakeSources.fromBytes([1, 0x01, 0, 0, 0, 0, 0]), isNull);
    });
  });
}
