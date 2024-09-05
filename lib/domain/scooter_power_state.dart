import 'dart:developer';

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
