import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/cloud_service.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/domain/scooter_state.dart';

Map<String, dynamic> payload({String? vehicleState, String? powerState, String? legacyState}) => {
      if (legacyState != null) 'state': legacyState,
      if (vehicleState != null || powerState != null)
        'telemetry': {
          if (vehicleState != null) 'vehicle_state': {'state': vehicleState},
          if (powerState != null) 'power': {'state': powerState},
        },
    };

void main() {
  group('scooterStateFromCloudData', () {
    test('reads vehicle state while the power manager is running', () {
      expect(
        scooterStateFromCloudData(payload(vehicleState: 'ready-to-drive', powerState: 'running')),
        ScooterState.ready,
      );
      expect(
        scooterStateFromCloudData(payload(vehicleState: 'stand-by', powerState: 'running')),
        ScooterState.standby,
      );
    });

    test('power state wins when the iMX6 is not usable', () {
      // sunshine reports the vehicle state it last saw, which is stale while
      // the scooter is hibernating, so the power state is what matters
      expect(
        scooterStateFromCloudData(payload(vehicleState: 'stand-by', powerState: 'hibernating')),
        ScooterState.hibernating,
      );
      expect(
        scooterStateFromCloudData(payload(vehicleState: 'stand-by', powerState: 'booting')),
        ScooterState.booting,
      );
    });

    test('covers the vehicle states sunshine can emit', () {
      const cases = {
        'unknown': ScooterState.unknown,
        'stand-by': ScooterState.standby,
        'parked': ScooterState.parked,
        'ready-to-drive': ScooterState.ready,
        'waiting-seatbox': ScooterState.waitingSeatbox,
        'shutting-down': ScooterState.shuttingDown,
        'updating': ScooterState.updating,
        'waiting-hibernation': ScooterState.waitingHibernation,
        'waiting-hibernation-advanced': ScooterState.waitingHibernationAdvanced,
        'waiting-hibernation-seatbox': ScooterState.waitingHibernationSeatbox,
        'waiting-hibernation-confirm': ScooterState.waitingHibernationConfirm,
      };
      for (final entry in cases.entries) {
        expect(
          scooterStateFromCloudData(payload(vehicleState: entry.key, powerState: 'running')),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('falls back to the legacy flat state field', () {
      expect(scooterStateFromCloudData(payload(legacyState: 'parked')), ScooterState.parked);
    });

    test('prefers telemetry over the legacy field', () {
      final data = payload(vehicleState: 'stand-by', powerState: 'hibernating', legacyState: 'stand-by');
      expect(scooterStateFromCloudData(data), ScooterState.hibernating);
    });

    test('returns null when there is nothing to go on', () {
      expect(scooterStateFromCloudData({}), isNull);
      expect(scooterStateFromCloudData({'telemetry': null}), isNull);
    });
  });

  group('ScooterPowerState.fromString', () {
    test('maps the scheduled-hibernation variants onto hibernating', () {
      for (final s in ['hibernating', 'hibernating-manual', 'hibernating-timer', 'hibernating-for']) {
        expect(ScooterPowerState.fromString(s), ScooterPowerState.hibernating, reason: s);
      }
      for (final s in [
        'hibernating-imminent',
        'hibernating-manual-imminent',
        'hibernating-timer-imminent',
        'hibernating-for-imminent',
      ]) {
        expect(ScooterPowerState.fromString(s), ScooterPowerState.hibernatingImminent, reason: s);
      }
    });

    test('maps the remaining canonical power states', () {
      expect(ScooterPowerState.fromString('active'), ScooterPowerState.running);
      expect(ScooterPowerState.fromString('running'), ScooterPowerState.running);
      expect(ScooterPowerState.fromString('booting'), ScooterPowerState.booting);
      expect(ScooterPowerState.fromString('suspending'), ScooterPowerState.suspending);
      expect(ScooterPowerState.fromString('suspending-pending'), ScooterPowerState.suspending);
      expect(ScooterPowerState.fromString('suspending-imminent'), ScooterPowerState.suspendingImminent);
      expect(ScooterPowerState.fromString('reboot'), ScooterPowerState.booting);
      expect(ScooterPowerState.fromString('reboot-imminent'), ScooterPowerState.booting);
    });

    test('still reports unknown strings as unknown', () {
      expect(ScooterPowerState.fromString('nonsense'), ScooterPowerState.unknown);
      expect(ScooterPowerState.fromString(null), isNull);
    });
  });
}
