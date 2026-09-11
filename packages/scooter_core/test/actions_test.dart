import 'package:scooter_core/actions.dart';
import 'package:test/test.dart';

void main() {
  test('persisted event enum names and order remain unchanged', () {
    expect(EventType.values.map((e) => e.toString()), [
      'EventType.lock',
      'EventType.unlock',
      'EventType.openSeat',
      'EventType.hibernate',
      'EventType.wakeUp',
      'EventType.unknown'
    ]);
    expect(EventSource.values.map((e) => e.toString()), [
      'EventSource.app',
      'EventSource.background',
      'EventSource.auto',
      'EventSource.unknown'
    ]);
  });
  test('immutable action defaults match service settings before restore', () {
    const settings = ActionSettings();
    expect(settings.openSeatOnUnlock, false);
    expect(settings.hazardLocking, false);
    expect(settings.warnOfUnlockedHandlebars, true);
    expect(settings.autoUnlockThreshold, -65);
    expect(settings.optionalAuth, false);
  });
  test('basic command strings and blink combinations are pinned', () {
    expect([
      unlockCommand,
      lockCommand,
      seatCommand,
      wakeCommand,
      hibernatePowerCommand
    ], [
      'scooter:state unlock',
      'scooter:state lock',
      'scooter:seatbox open',
      'wakeup',
      'hibernate'
    ]);
    expect([
      blinkerCommand(true, false),
      blinkerCommand(false, true),
      blinkerCommand(true, true),
      blinkerCommand(false, false)
    ], [
      'scooter:blinker left',
      'scooter:blinker right',
      'scooter:blinker both',
      'scooter:blinker off'
    ]);
  });
  test(
      'duration validation preserves truncation and positive subsecond hibernation',
      () {
    expect(autoStandbyValue(const Duration(milliseconds: -1)), '0');
    expect(autoStandbyValue(const Duration(seconds: 3600)), '3600');
    expect(() => autoStandbyValue(const Duration(seconds: -1)),
        throwsA('Auto-standby time cannot be negative'));
    expect(() => autoStandbyValue(const Duration(seconds: 3601)),
        throwsA('Auto-standby time cannot be greater than 1 hour'));
    expect(hibernateForPayload(const Duration(milliseconds: 1)),
        'pm:hibernate-for 0s');
    expect(() => hibernateForPayload(Duration.zero),
        throwsA('Hibernate wake timer must be positive'));
  });
  test('keycard identifiers and APN trailing space are not normalized', () {
    expect(addKeycardPayload('A:B'), 'keycard:add:A:B');
    expect(deleteKeycardPayload('A:B'), 'keycard:remove:A:B');
    expect(apnCommandPrefix, 'config:apn ');
    expect(checkApn('a' * maxApnLength), null);
    expect(checkApn('a' * (maxApnLength + 1)), ApnProblem.tooLong);
    expect(checkApn('two words'), ApnProblem.invalidCharacters);
    expect(checkApn(''), ApnProblem.empty);
  });
}
