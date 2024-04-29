
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
  });
}
