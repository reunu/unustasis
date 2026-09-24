import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';

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

}
