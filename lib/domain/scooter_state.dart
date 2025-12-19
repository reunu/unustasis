import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import '../domain/scooter_power_state.dart';
import '../domain/scooter_vehicle_state.dart';

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

  static ScooterState? fromVehicleAndPowerState(ScooterVehicleState? vehicleState, ScooterPowerState? powerState) {
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
        return vehicleState != null ? fromVehicleAndPowerState(vehicleState, ScooterPowerState.running) : null;
    }
  }
}

extension StateExtension on ScooterState {
  Color color(BuildContext context) {
    switch (this) {
      case ScooterState.off:
      case ScooterState.hibernating:
      case ScooterState.hibernatingImminent:
      case ScooterState.booting:
      case ScooterState.shuttingDown:
        // scooter is connected and actionable, but asleep
        return Colors.grey.shade200;
      case ScooterState.standby:
      case ScooterState.updating:
        // scooter is in standby/updating - treat like standby
        return Colors.grey.shade200;
      case ScooterState.ready:
      case ScooterState.parked:
      case ScooterState.waitingSeatbox:
      case ScooterState.waitingHibernation:
      case ScooterState.waitingHibernationAdvanced:
      case ScooterState.waitingHibernationSeatbox:
      case ScooterState.waitingHibernationConfirm:
        // scooter is awake and ready to party!
        return Theme.of(context).colorScheme.primary;
      case ScooterState.unknown:
      case ScooterState.disconnected:
      default:
        // scooter is disconnected or in a bad state (like Bavaria or sth)
        return Theme.of(context).colorScheme.surfaceContainer;
    }
  }

  String name(BuildContext context) {
    switch (this) {
      case ScooterState.standby:
        return FlutterI18n.translate(context, "state_name_standby");
      case ScooterState.off:
        return FlutterI18n.translate(context, "state_name_off");
      case ScooterState.parked:
        return FlutterI18n.translate(context, "state_name_parked");
      case ScooterState.shuttingDown:
        return FlutterI18n.translate(context, "state_name_shutting_down");
      case ScooterState.ready:
        return FlutterI18n.translate(context, "state_name_ready");
      case ScooterState.updating:
        return FlutterI18n.translate(context, "state_name_updating");
      case ScooterState.waitingSeatbox:
        return FlutterI18n.translate(context, "state_name_waiting_seatbox");
      case ScooterState.waitingHibernation:
      case ScooterState.waitingHibernationAdvanced:
      case ScooterState.waitingHibernationSeatbox:
      case ScooterState.waitingHibernationConfirm:
        return FlutterI18n.translate(context, "state_name_waiting_hibernation");
      case ScooterState.hibernating:
        return FlutterI18n.translate(context, "state_name_hibernating");
      case ScooterState.hibernatingImminent:
        return FlutterI18n.translate(context, "state_name_hibernating_imminent");
      case ScooterState.booting:
        return FlutterI18n.translate(context, "state_name_booting");
      case ScooterState.unknown:
        return FlutterI18n.translate(context, "state_name_unknown");
      case ScooterState.disconnected:
        return FlutterI18n.translate(context, "state_name_disconnected");
      case ScooterState.linking:
        return FlutterI18n.translate(context, "state_name_linking");
    }
  }

  String description(BuildContext context) {
    switch (this) {
      case ScooterState.standby:
        return FlutterI18n.translate(context, "state_desc_standby");
      case ScooterState.off:
        return FlutterI18n.translate(context, "state_desc_off");
      case ScooterState.parked:
        return FlutterI18n.translate(context, "state_desc_parked");
      case ScooterState.shuttingDown:
        return FlutterI18n.translate(context, "state_desc_shutting_down");
      case ScooterState.ready:
        return FlutterI18n.translate(context, "state_desc_ready");
      case ScooterState.updating:
        return FlutterI18n.translate(context, "state_desc_updating");
      case ScooterState.waitingSeatbox:
        return FlutterI18n.translate(context, "state_desc_waiting_seatbox");
      case ScooterState.waitingHibernation:
      case ScooterState.waitingHibernationAdvanced:
      case ScooterState.waitingHibernationSeatbox:
      case ScooterState.waitingHibernationConfirm:
        return FlutterI18n.translate(context, "state_desc_waiting_hibernation");
      case ScooterState.hibernating:
        return FlutterI18n.translate(context, "state_desc_hibernating");
      case ScooterState.hibernatingImminent:
        return FlutterI18n.translate(context, "state_desc_hibernating_imminent");
      case ScooterState.booting:
        return FlutterI18n.translate(context, "state_desc_booting");
      case ScooterState.unknown:
        return FlutterI18n.translate(context, "state_desc_unknown");
      case ScooterState.disconnected:
        return FlutterI18n.translate(context, "state_desc_disconnected");
      case ScooterState.linking:
        return FlutterI18n.translate(context, "state_desc_linking");
    }
  }

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
      case ScooterState.booting:
        return false;
      default:
        return true;
    }
  }
}
