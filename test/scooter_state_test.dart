
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/scooter_state.dart';

void main() {
  group('ScooterState', () {
    test('fromStateAndPowerState', () {
      expect(ScooterState.fromStateAndPowerState('off', 'hibernating'), equals(ScooterState.hibernating));
      expect(ScooterState.fromStateAndPowerState('stand-by', 'hibernating-imminent'), equals(ScooterState.hibernatingImminent));
      expect(ScooterState.fromStateAndPowerState('off', 'booting'), equals(ScooterState.booting));

      // see https://github.com/reunu/unustasis/issues/20
      expect(ScooterState.fromStateAndPowerState('stand-by', 'booting'), equals(ScooterState.standby));

      expect(ScooterState.fromStateAndPowerState('stand-by', 'running'), equals(ScooterState.standby));
      expect(ScooterState.fromStateAndPowerState('off', 'suspending'), equals(ScooterState.off));
      expect(ScooterState.fromStateAndPowerState('parked', 'running'), equals(ScooterState.parked));
      expect(ScooterState.fromStateAndPowerState('shutting-down', ''), equals(ScooterState.shuttingDown));
      expect(ScooterState.fromStateAndPowerState('ready-to-drive', 'running'), equals(ScooterState.ready));

      expect(ScooterState.fromStateAndPowerState('', ''), equals(ScooterState.unknown));
      expect(ScooterState.fromStateAndPowerState('unknown', ''), equals(ScooterState.unknown));
    });

    test('isOn', () {
      expect(ScooterState.standby.isOn, false);
      expect(ScooterState.off.isOn, false);
      expect(ScooterState.parked.isOn, true);
      expect(ScooterState.shuttingDown.isOn, false);
      expect(ScooterState.ready.isOn, true);
      expect(ScooterState.hibernating.isOn, false);
      expect(ScooterState.hibernatingImminent.isOn, false);
      expect(ScooterState.booting.isOn, false);
      expect(ScooterState.unknown.isOn, false);
      expect(ScooterState.linking.isOn, false);
      expect(ScooterState.disconnected.isOn, false);
    });

    test('isReadyForLockChange', () {
      expect(ScooterState.standby.isReadyForLockChange, true);
      expect(ScooterState.off.isReadyForLockChange, true);
      expect(ScooterState.parked.isReadyForLockChange, true);
      expect(ScooterState.shuttingDown.isReadyForLockChange, false);
      expect(ScooterState.ready.isReadyForLockChange, true);
      expect(ScooterState.hibernating.isReadyForLockChange, true);
      expect(ScooterState.hibernatingImminent.isReadyForLockChange, true);
      expect(ScooterState.booting.isReadyForLockChange, false);
      expect(ScooterState.unknown.isReadyForLockChange, false);
      expect(ScooterState.linking.isReadyForLockChange, false);
      expect(ScooterState.disconnected.isReadyForLockChange, false);
    });
  });
}
