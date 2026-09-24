import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/alarm_status.dart';
import 'package:unustasis/state/vehicle_status.dart';

void main() {
  group('AlarmStatus.fromString', () {
    test('maps the wire strings', () {
      expect(AlarmStatus.fromString("disabled"), AlarmStatus.disabled);
      expect(AlarmStatus.fromString("disarmed"), AlarmStatus.disarmed);
      expect(AlarmStatus.fromString("delay-armed"), AlarmStatus.delayArmed);
      expect(AlarmStatus.fromString("armed"), AlarmStatus.armed);
      expect(AlarmStatus.fromString("level-1-triggered"), AlarmStatus.level1Triggered);
      expect(AlarmStatus.fromString("level-2-triggered"), AlarmStatus.level2Triggered);
      expect(AlarmStatus.fromString("seatbox-access"), AlarmStatus.seatboxAccess);
    });

    test('passes null through and falls back to unknown', () {
      expect(AlarmStatus.fromString(null), isNull);
      expect(AlarmStatus.fromString("something-new"), AlarmStatus.unknown);
    });
  });

  group('parseAlarmLastTrigger', () {
    test('splits the source from the timestamp', () {
      final trigger = parseAlarmLastTrigger("motion,2026-09-04T18:30:00Z");
      expect(trigger, isNotNull);
      expect(trigger!.source, "motion");
      expect(trigger.timestamp, DateTime.utc(2026, 9, 4, 18, 30));
    });

    test('keeps the source when the timestamp is unparseable or missing', () {
      expect(parseAlarmLastTrigger("seatbox,nonsense")?.source, "seatbox");
      expect(parseAlarmLastTrigger("seatbox,nonsense")?.timestamp, isNull);
      expect(parseAlarmLastTrigger("seatbox")?.source, "seatbox");
      expect(parseAlarmLastTrigger("seatbox")?.timestamp, isNull);
    });

    test('returns null when there is no source', () {
      expect(parseAlarmLastTrigger(""), isNull);
      expect(parseAlarmLastTrigger(",2026-09-04T18:30:00Z"), isNull);
    });
  });
}
