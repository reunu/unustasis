import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';

enum ScooterPowerState {
  booting,
  running,
  suspending,
  suspendingImminent,
  hibernating,
  hibernatingImminent,
  unknown;

  static ScooterPowerState? fromString(String? powerState) {
    final log = Logger("ScooterPowerState");

    switch (powerState) {
      case "booting":
        return ScooterPowerState.booting;
      case "running":
        return ScooterPowerState.running;
      case "suspending":
        return ScooterPowerState.suspending;
      case "suspending-imminent":
        return ScooterPowerState.suspendingImminent;
      case "hibernating":
        return ScooterPowerState.hibernating;
      case "hibernating-imminent":
        return ScooterPowerState.hibernatingImminent;
      case null:
        return null;
      default:
        log.warning("Unknown state: $powerState");
        return ScooterPowerState.unknown;
    }
  }
}

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
