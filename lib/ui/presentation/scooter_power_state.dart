import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';

extension PowerStateExtension on ScooterPowerState {
  String name(BuildContext context) {
    switch (this) {
      case ScooterPowerState.booting:
        return FlutterI18n.translate(context, "power_state_booting");
      case ScooterPowerState.running:
        return FlutterI18n.translate(context, "power_state_running");
      case ScooterPowerState.suspending:
        return FlutterI18n.translate(context, "power_state_suspending");
      case ScooterPowerState.suspendingImminent:
        return FlutterI18n.translate(context, "power_state_suspending_imminent");
      case ScooterPowerState.hibernating:
        return FlutterI18n.translate(context, "power_state_hibernating");
      case ScooterPowerState.hibernatingImminent:
        return FlutterI18n.translate(context, "power_state_hibernating_imminent");
      case ScooterPowerState.unknown:
        return FlutterI18n.translate(context, "power_state_unknown");
    }
  }
}
