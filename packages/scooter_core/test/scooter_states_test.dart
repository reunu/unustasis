import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:test/test.dart';

void main() {
  test('wire mappings retain enum ordering and nullable/unknown semantics', () {
    const vehicleWires = [
      'stand-by',
      'off',
      'parked',
      'shutting-down',
      'ready-to-drive',
      'waiting-seatbox',
      'updating',
      'waiting-hibernation',
      'waiting-hibernation-advanced',
      'waiting-hibernation-seatbox',
      'waiting-hibernation-confirm',
      '',
    ];
    const powerWires = [
      'booting',
      'running',
      'suspending',
      'suspending-imminent',
      'hibernating',
      'hibernating-imminent',
      'unknown',
    ];
    const alarmWires = [
      'disabled',
      'disarmed',
      'delay-armed',
      'armed',
      'level-1-triggered',
      'level-2-triggered',
      'seatbox-access',
      'unknown',
    ];
    const aggregateNames = [
      'standby',
      'off',
      'parked',
      'shuttingDown',
      'ready',
      'waitingSeatbox',
      'updating',
      'waitingHibernation',
      'waitingHibernationAdvanced',
      'waitingHibernationSeatbox',
      'waitingHibernationConfirm',
      'hibernating',
      'hibernatingImminent',
      'booting',
      'unknown',
      'linking',
      'disconnected',
    ];
    expect(ScooterState.values.map((state) => state.name), aggregateNames);
    expect(vehicleWires.map(ScooterVehicleState.fromString),
        ScooterVehicleState.values);
    expect(
        powerWires.map(ScooterPowerState.fromString), ScooterPowerState.values);
    expect(alarmWires.map(AlarmStatus.fromString), AlarmStatus.values);
    const aggregateWires = {
      'stand-by': ScooterState.standby,
      'off': ScooterState.off,
      'parked': ScooterState.parked,
      'shutting-down': ScooterState.shuttingDown,
      'ready-to-drive': ScooterState.ready,
      'hibernating': ScooterState.hibernating,
      'hibernating-imminent': ScooterState.hibernatingImminent,
      'booting': ScooterState.booting,
      '': ScooterState.unknown,
    };
    for (final entry in aggregateWires.entries) {
      expect(ScooterState.fromString(entry.key), entry.value);
    }
    for (final wire in [
      'waiting-seatbox',
      'updating',
      'waiting-hibernation',
      'waiting-hibernation-advanced',
      'waiting-hibernation-seatbox',
      'waiting-hibernation-confirm',
      'linking',
      'disconnected',
      'unknown'
    ]) {
      expect(ScooterState.fromString(wire), ScooterState.unknown);
    }
    expect(ScooterState.fromString(null), isNull);
    expect(ScooterVehicleState.fromString(null), isNull);
    expect(ScooterPowerState.fromString(null), isNull);
    expect(AlarmStatus.fromString(null), isNull);
    for (final wire in ['', 'unknown', 'INVALID', ' running ']) {
      expect(ScooterState.fromString(wire), ScooterState.unknown);
      expect(ScooterVehicleState.fromString(wire), ScooterVehicleState.unknown);
      expect(ScooterPowerState.fromString(wire), ScooterPowerState.unknown);
      expect(AlarmStatus.fromString(wire), AlarmStatus.unknown);
    }
  });

  test('warning logger names, levels, messages and silent empty states persist',
      () async {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    ScooterState.fromString(null);
    ScooterVehicleState.fromString(null);
    ScooterPowerState.fromString(null);
    AlarmStatus.fromString(null);
    ScooterState.fromString('');
    ScooterVehicleState.fromString('');
    expect(records, isEmpty);
    ScooterState.fromString('bad');
    ScooterVehicleState.fromString('bad');
    ScooterPowerState.fromString('');
    AlarmStatus.fromString('');
    expect(records.map((record) => record.loggerName), [
      'ScooterState.fromStateString',
      'ScooterVehicleState.fromString',
      'ScooterPowerState',
      'AlarmStatus',
    ]);
    expect(records.map((record) => record.message), [
      'Unknown state: bad',
      'Unknown vehicle state: bad',
      'Unknown state: ',
      'Unknown status: ',
    ]);
    expect(records.every((record) => record.level == Level.WARNING), isTrue);
  });

  test(
      'every vehicle/power pair including null and unknown aggregates identically',
      () {
    const vehicleResults = [
      ScooterState.standby,
      ScooterState.off,
      ScooterState.parked,
      ScooterState.shuttingDown,
      ScooterState.ready,
      ScooterState.waitingSeatbox,
      ScooterState.updating,
      ScooterState.waitingHibernation,
      ScooterState.waitingHibernationAdvanced,
      ScooterState.waitingHibernationSeatbox,
      ScooterState.waitingHibernationConfirm,
      ScooterState.unknown,
    ];
    for (final vehicle in <ScooterVehicleState?>[
      null,
      ...ScooterVehicleState.values
    ]) {
      for (final power in <ScooterPowerState?>[
        null,
        ...ScooterPowerState.values
      ]) {
        final expected = switch (power) {
          ScooterPowerState.booting => ScooterState.booting,
          ScooterPowerState.hibernating => ScooterState.hibernating,
          ScooterPowerState.hibernatingImminent =>
            ScooterState.hibernatingImminent,
          _ => vehicle == null ? null : vehicleResults[vehicle.index],
        };
        expect(ScooterState.fromVehicleAndPowerState(vehicle, power), expected,
            reason: 'vehicle=$vehicle power=$power');
      }
    }
  });

  test('all state permissions remain unchanged', () {
    const on = {
      ScooterState.parked,
      ScooterState.ready,
      ScooterState.waitingSeatbox,
      ScooterState.waitingHibernation,
      ScooterState.waitingHibernationAdvanced,
      ScooterState.waitingHibernationSeatbox,
      ScooterState.waitingHibernationConfirm
    };
    const lock = {
      ...on,
      ScooterState.off,
      ScooterState.standby,
      ScooterState.updating,
      ScooterState.hibernating,
      ScooterState.hibernatingImminent
    };
    const noSeat = {
      ScooterState.hibernating,
      ScooterState.hibernatingImminent,
      ScooterState.booting
    };
    const reboot = {
      ScooterState.standby,
      ScooterState.parked,
      ScooterState.ready
    };
    for (final state in ScooterState.values) {
      expect(state.isOn, on.contains(state), reason: '$state isOn');
      expect(state.isReadyForLockChange, lock.contains(state),
          reason: '$state lock');
      expect(state.isReadyForSeatOpen, !noSeat.contains(state),
          reason: '$state seat');
      expect(state.permitsHardReboot, reboot.contains(state),
          reason: '$state reboot');
    }
  });
}
