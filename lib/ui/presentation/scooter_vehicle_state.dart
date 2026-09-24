import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';

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
