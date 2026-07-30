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
      case "active":
        return ScooterPowerState.running;
      case "suspending":
      case "suspending-pending":
        return ScooterPowerState.suspending;
      case "suspending-imminent":
        return ScooterPowerState.suspendingImminent;
      // the manual/timer/for variants differ only in what scheduled the
      // hibernation, which we don't surface separately
      case "hibernating":
      case "hibernating-manual":
      case "hibernating-timer":
      case "hibernating-for":
        return ScooterPowerState.hibernating;
      case "hibernating-imminent":
      case "hibernating-manual-imminent":
      case "hibernating-timer-imminent":
      case "hibernating-for-imminent":
        return ScooterPowerState.hibernatingImminent;
      // a reboot leaves the iMX6 unusable in the same way booting does
      case "reboot":
      case "reboot-imminent":
        return ScooterPowerState.booting;
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
