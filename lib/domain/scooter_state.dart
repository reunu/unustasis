import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import 'package:logging/logging.dart';
import '../domain/scooter_power_state.dart';

enum ScooterState {
  standby,
  off,
  parked,
  shuttingDown,
  ready,
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

  static ScooterState? fromStateAndPowerState(
      ScooterState? state, ScooterPowerState? powerState) {
    switch (powerState) {
      case ScooterPowerState.booting:
        return ScooterState.booting;
      case ScooterPowerState.hibernating:
        return ScooterState.hibernating;
      case ScooterPowerState.hibernatingImminent:
        return ScooterState.hibernatingImminent;
      case ScooterPowerState.suspendingImminent:
        return ScooterState.shuttingDown;
      case ScooterPowerState.suspending:
        if (state != ScooterState.standby) {
          return ScooterState.off;
        } else {
          return state;
        }
      default:
        return state;
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
      case ScooterState.ready:
      case ScooterState.parked:
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
      case ScooterState.hibernating:
        return FlutterI18n.translate(context, "state_name_hibernating");
      case ScooterState.hibernatingImminent:
        return FlutterI18n.translate(
            context, "state_name_hibernating_imminent");
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
      case ScooterState.hibernating:
        return FlutterI18n.translate(context, "state_desc_hibernating");
      case ScooterState.hibernatingImminent:
        return FlutterI18n.translate(
            context, "state_desc_hibernating_imminent");
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
        return true;
      default:
        return false;
    }
  }

  bool get isReadyForLockChange {
    switch (this) {
      case ScooterState.off: // hibernating states can be missing
      case ScooterState.standby:
      case ScooterState.hibernating:
      case ScooterState.hibernatingImminent:
      case ScooterState.parked:
      case ScooterState.ready:
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
}
