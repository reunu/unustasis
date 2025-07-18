import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/domain/scooter_state.dart';

void main() {
  group('ScooterState', () {
    test('fromStateAndPowerState', () {
      expect(
          ScooterState.fromStateAndPowerState('off', ScooterPowerState.hibernating), equals(ScooterState.hibernating));
      expect(ScooterState.fromStateAndPowerState('stand-by', ScooterPowerState.hibernatingImminent),
          equals(ScooterState.hibernatingImminent));
      expect(ScooterState.fromStateAndPowerState('off', ScooterPowerState.booting), equals(ScooterState.booting));

      // see https://github.com/reunu/unustasis/issues/20
      expect(ScooterState.fromStateAndPowerState('stand-by', ScooterPowerState.booting), equals(ScooterState.standby));

      expect(ScooterState.fromStateAndPowerState('stand-by', ScooterPowerState.running), equals(ScooterState.standby));
      expect(ScooterState.fromStateAndPowerState('off', ScooterPowerState.suspending), equals(ScooterState.off));
      expect(ScooterState.fromStateAndPowerState('parked', ScooterPowerState.running), equals(ScooterState.parked));
      expect(ScooterState.fromStateAndPowerState('shutting-down', ScooterPowerState.unknown),
          equals(ScooterState.shuttingDown));
      expect(
          ScooterState.fromStateAndPowerState('ready-to-drive', ScooterPowerState.running), equals(ScooterState.ready));

      expect(ScooterState.fromStateAndPowerState('', ScooterPowerState.unknown), equals(ScooterState.unknown));
      expect(ScooterState.fromStateAndPowerState('unknown', ScooterPowerState.unknown), equals(ScooterState.unknown));
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
