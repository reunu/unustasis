import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';

enum ScooterVehicleState {
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
  unknown;

  static ScooterVehicleState? fromString(String? state) {
    final log = Logger("ScooterVehicleState.fromString");
    switch (state) {
      case "stand-by":
        return ScooterVehicleState.standby;
      case "off":
        return ScooterVehicleState.off;
      case "parked":
        return ScooterVehicleState.parked;
      case "shutting-down":
        return ScooterVehicleState.shuttingDown;
      case "ready-to-drive":
        return ScooterVehicleState.ready;
      case "waiting-seatbox":
        return ScooterVehicleState.waitingSeatbox;
      case "updating":
        return ScooterVehicleState.updating;
      case "waiting-hibernation":
        return ScooterVehicleState.waitingHibernation;
      case "waiting-hibernation-advanced":
        return ScooterVehicleState.waitingHibernationAdvanced;
      case "waiting-hibernation-seatbox":
        return ScooterVehicleState.waitingHibernationSeatbox;
      case "waiting-hibernation-confirm":
        return ScooterVehicleState.waitingHibernationConfirm;
      case "":
        // this is sometimes sent during standby, off or hibernating...
        return ScooterVehicleState.unknown;
      case null:
        return null;
      default:
        log.warning("Unknown vehicle state: $state");
        return ScooterVehicleState.unknown;
    }
  }
}

extension VehicleStateExtension on ScooterVehicleState {
  String name(BuildContext context) {
    switch (this) {
      case ScooterVehicleState.standby:
        return FlutterI18n.translate(context, "state_name_standby");
      case ScooterVehicleState.off:
        return FlutterI18n.translate(context, "state_name_off");
      case ScooterVehicleState.parked:
        return FlutterI18n.translate(context, "state_name_parked");
      case ScooterVehicleState.shuttingDown:
        return FlutterI18n.translate(context, "state_name_shutting_down");
      case ScooterVehicleState.ready:
        return FlutterI18n.translate(context, "state_name_ready");
      case ScooterVehicleState.waitingSeatbox:
        return FlutterI18n.translate(context, "state_name_waiting_seatbox");
      case ScooterVehicleState.updating:
        return FlutterI18n.translate(context, "state_name_updating");
      case ScooterVehicleState.waitingHibernation:
      case ScooterVehicleState.waitingHibernationAdvanced:
      case ScooterVehicleState.waitingHibernationSeatbox:
      case ScooterVehicleState.waitingHibernationConfirm:
        return FlutterI18n.translate(context, "state_name_waiting_hibernation");
      case ScooterVehicleState.unknown:
        return FlutterI18n.translate(context, "state_name_unknown");
    }
  }
}
