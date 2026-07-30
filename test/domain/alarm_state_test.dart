import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/alarm_state.dart';

void main() {
  group('alarmActionFor', () {
    test('an armed alarm offers disarm', () {
      expect(alarmActionFor('armed'), AlarmAction.disarm);
      expect(alarmActionFor('delay-armed'), AlarmAction.disarm);
    });

    test('a disarmed alarm offers arm', () {
      expect(alarmActionFor('disarmed'), AlarmAction.arm);
      expect(alarmActionFor('seatbox-access'), AlarmAction.arm);
    });

    test('a triggered alarm offers stop', () {
      expect(alarmActionFor('level-1-triggered'), AlarmAction.stop);
      expect(alarmActionFor('level-2-triggered'), AlarmAction.stop);
    });

    test('a disabled or unknown alarm offers nothing', () {
      expect(alarmActionFor('disabled'), isNull);
      expect(alarmActionFor(null), isNull);
      expect(alarmActionFor('something-new'), isNull);
    });
  });

  group('alarmStateI18nKey', () {
    test('maps every known state to its own key', () {
      const states = [
        'armed',
        'delay-armed',
        'disarmed',
        'seatbox-access',
        'level-1-triggered',
        'level-2-triggered',
        'disabled',
      ];
      final keys = states.map(alarmStateI18nKey).toSet();
      expect(keys.length, states.length, reason: 'each state needs a distinct key');
      expect(keys.every((k) => k.startsWith('alarm_state_')), isTrue);
    });

    test('falls back to unknown', () {
      expect(alarmStateI18nKey(null), 'alarm_state_unknown');
      expect(alarmStateI18nKey('something-new'), 'alarm_state_unknown');
    });
  });
}
