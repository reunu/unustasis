import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/hibernation_schedule.dart';

void main() {
  group('HibernationSchedule.fromCron', () {
    test('parses a daily schedule', () {
      final schedule = HibernationSchedule.fromCron("0 22 * * *");
      expect(schedule, isNotNull);
      expect(schedule!.hour, 22);
      expect(schedule.minute, 0);
      expect(schedule.frequency, HibernationFrequency.daily);
    });

    test('parses weekday lists as weekly', () {
      final schedule = HibernationSchedule.fromCron("30 7 * * 0,6");
      expect(schedule, isNotNull);
      expect(schedule!.hour, 7);
      expect(schedule.minute, 30);
      expect(schedule.frequency, HibernationFrequency.weekly);
      expect(schedule.weekdays, {0, 6});
    });

    test('keeps a full weekday list as weekly', () {
      final schedule = HibernationSchedule.fromCron("0 22 * * 0,1,2,3,4,5,6");
      expect(schedule, isNotNull);
      expect(schedule!.frequency, HibernationFrequency.weekly);
      expect(schedule.weekdays, HibernationSchedule.allDays);
    });

    test('maps cron 7 to Sunday', () {
      final schedule = HibernationSchedule.fromCron("30 7 * * 7");
      expect(schedule, isNotNull);
      expect(schedule!.weekdays, {0});
    });

    test('parses a day of month as monthly', () {
      final schedule = HibernationSchedule.fromCron("0 3 15 * *");
      expect(schedule, isNotNull);
      expect(schedule!.frequency, HibernationFrequency.monthly);
      expect(schedule.dayOfMonth, 15);
    });

    test('tolerates extra whitespace', () {
      final schedule = HibernationSchedule.fromCron("  30   7 * * 1 ");
      expect(schedule, isNotNull);
      expect(schedule!.weekdays, {1});
    });

    test('rejects expressions outside the supported subset', () {
      expect(HibernationSchedule.fromCron(""), isNull);
      expect(HibernationSchedule.fromCron("30 7 * * 1-5"), isNull); // range
      expect(HibernationSchedule.fromCron("*/5 * * * *"), isNull); // step
      expect(HibernationSchedule.fromCron("30 7 */2 * *"), isNull); // dom step
      expect(HibernationSchedule.fromCron("30 7 1 * 1"), isNull); // dom + dow
      expect(HibernationSchedule.fromCron("30 7 * 6 *"), isNull); // month set
      expect(HibernationSchedule.fromCron("30 7 0 * *"), isNull); // bad dom
      expect(HibernationSchedule.fromCron("30 7 32 * *"), isNull); // bad dom
      expect(HibernationSchedule.fromCron("30 7 * * MON"), isNull); // name
      expect(HibernationSchedule.fromCron("60 7 * * *"), isNull); // bad minute
      expect(HibernationSchedule.fromCron("30 24 * * *"), isNull); // bad hour
      expect(HibernationSchedule.fromCron("30 7 * * 8"), isNull); // bad dow
      expect(HibernationSchedule.fromCron("30 7 * *"), isNull); // 4 fields
    });
  });

  group('HibernationSchedule.toCron', () {
    test('emits * fields for daily', () {
      const schedule = HibernationSchedule(hour: 22, minute: 0);
      expect(schedule.toCron(), "0 22 * * *");
    });

    test('emits a sorted weekday list for weekly', () {
      const schedule = HibernationSchedule(
        hour: 7,
        minute: 30,
        frequency: HibernationFrequency.weekly,
        weekdays: {6, 0, 3},
      );
      expect(schedule.toCron(), "30 7 * * 0,3,6");
    });

    test('emits an explicit list for weekly with all days', () {
      const schedule = HibernationSchedule(
        hour: 22,
        minute: 0,
        frequency: HibernationFrequency.weekly,
      );
      expect(schedule.toCron(), "0 22 * * 0,1,2,3,4,5,6");
    });

    test('emits the day of month for monthly', () {
      const schedule = HibernationSchedule(
        hour: 3,
        minute: 0,
        frequency: HibernationFrequency.monthly,
        dayOfMonth: 15,
      );
      expect(schedule.toCron(), "0 3 15 * *");
    });

    test('round-trips through fromCron for all frequencies', () {
      const schedules = [
        HibernationSchedule(hour: 23, minute: 15),
        HibernationSchedule(
          hour: 23,
          minute: 15,
          frequency: HibernationFrequency.weekly,
          weekdays: {1, 2, 3, 4, 5},
        ),
        HibernationSchedule(
          hour: 23,
          minute: 15,
          frequency: HibernationFrequency.weekly,
        ),
        HibernationSchedule(
          hour: 23,
          minute: 15,
          frequency: HibernationFrequency.monthly,
          dayOfMonth: 31,
        ),
      ];
      for (final original in schedules) {
        final parsed = HibernationSchedule.fromCron(original.toCron());
        expect(parsed, isNotNull, reason: original.toCron());
        expect(parsed!.hour, original.hour);
        expect(parsed.minute, original.minute);
        expect(parsed.frequency, original.frequency);
        if (original.frequency == HibernationFrequency.weekly) {
          expect(parsed.weekdays, original.weekdays);
        }
        if (original.frequency == HibernationFrequency.monthly) {
          expect(parsed.dayOfMonth, original.dayOfMonth);
        }
      }
    });
  });
}
