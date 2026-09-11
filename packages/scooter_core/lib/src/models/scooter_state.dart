import 'package:logging/logging.dart';

import 'scooter_power_state.dart';
import 'scooter_vehicle_state.dart';

enum ScooterState {
  standby,
  off,
  parked,
  shuttingDown,
  ready,
  waitingSeatbox,
  updating,
  waitingHibernation,
  waitingHibernationAdvanced,
  waitingHibernationSeatbox,
  waitingHibernationConfirm,
  hibernating,
  hibernatingImminent,
  booting,
  unknown,
  linking,
  disconnected;

  static ScooterState? fromString(String? state) {
    final log = Logger("ScooterState.fromStateString");
    switch (state) {
      case "stand-by":
        return ScooterState.standby;
      case "off":
        return ScooterState.off;
      case "parked":
        return ScooterState.parked;
      case "shutting-down":
        return ScooterState.shuttingDown;
      case "ready-to-drive":
        return ScooterState.ready;
      case "hibernating":
        return ScooterState.hibernating;
      case "hibernating-imminent":
        return ScooterState.hibernatingImminent;
      case "booting":
        return ScooterState.booting;
      case "":
        // this is sometimes sent during standby, off or hibernating...
        return ScooterState.unknown;
      case null:
        return null;
      default:
        log.warning("Unknown state: $state");
        return ScooterState.unknown;
    }
  }

  static ScooterState? fromVehicleAndPowerState(
      ScooterVehicleState? vehicleState, ScooterPowerState? powerState) {
    // When PM state is running, suspending, or suspending-imminent, use vehicle state (iMX6 is usable)
    // Otherwise, use PM state (iMX6 is not usable - booting or hibernating)
    if (powerState == ScooterPowerState.running ||
        powerState == ScooterPowerState.suspending ||
        powerState == ScooterPowerState.suspendingImminent) {
      // Map vehicle state to aggregate ScooterState
      if (vehicleState == null) return null;
      switch (vehicleState) {
        case ScooterVehicleState.standby:
          return ScooterState.standby;
        case ScooterVehicleState.off:
          return ScooterState.off;
        case ScooterVehicleState.parked:
          return ScooterState.parked;
        case ScooterVehicleState.shuttingDown:
          return ScooterState.shuttingDown;
        case ScooterVehicleState.ready:
          return ScooterState.ready;
        case ScooterVehicleState.waitingSeatbox:
          return ScooterState.waitingSeatbox;
        case ScooterVehicleState.updating:
          return ScooterState.updating;
        case ScooterVehicleState.waitingHibernation:
          return ScooterState.waitingHibernation;
        case ScooterVehicleState.waitingHibernationAdvanced:
          return ScooterState.waitingHibernationAdvanced;
        case ScooterVehicleState.waitingHibernationSeatbox:
          return ScooterState.waitingHibernationSeatbox;
        case ScooterVehicleState.waitingHibernationConfirm:
          return ScooterState.waitingHibernationConfirm;
        case ScooterVehicleState.unknown:
          return ScooterState.unknown;
      }
    }

    // iMX6 is not usable - reflect PM state
    switch (powerState) {
      case ScooterPowerState.booting:
        return ScooterState.booting;
      case ScooterPowerState.hibernating:
        return ScooterState.hibernating;
      case ScooterPowerState.hibernatingImminent:
        return ScooterState.hibernatingImminent;
      default:
        // Fallback to vehicle state if PM state is unknown
        return vehicleState != null
            ? fromVehicleAndPowerState(vehicleState, ScooterPowerState.running)
            : null;
    }
  }
}

extension ScooterStatePermissions on ScooterState {
  bool get isOn {
    switch (this) {
      case ScooterState.parked:
      case ScooterState.ready:
      case ScooterState.waitingSeatbox:
      case ScooterState.waitingHibernation:
      case ScooterState.waitingHibernationAdvanced:
      case ScooterState.waitingHibernationSeatbox:
      case ScooterState.waitingHibernationConfirm:
        return true;
      default:
        return false;
    }
  }

  bool get isReadyForLockChange {
    switch (this) {
      case ScooterState.off:
      case ScooterState.standby:
      case ScooterState.updating:
      case ScooterState.hibernating:
      case ScooterState.hibernatingImminent:
      case ScooterState.parked:
      case ScooterState.ready:
      case ScooterState.waitingSeatbox:
      case ScooterState.waitingHibernation:
      case ScooterState.waitingHibernationAdvanced:
      case ScooterState.waitingHibernationSeatbox:
      case ScooterState.waitingHibernationConfirm:
        return true;
      default:
        return false;
    }
  }

  bool get isReadyForSeatOpen {
    switch (this) {
      case ScooterState.hibernating:
      case ScooterState.hibernatingImminent:
      case ScooterState.booting:
        return false;
      default:
        return true;
    }
  }

  bool get permitsHardReboot {
    switch (this) {
      case ScooterState.standby:
      case ScooterState.parked:
      case ScooterState.ready:
        return true;
      default:
        return false;
    }
  }
}
