import 'dart:developer';

enum ScooterPowerState {
  booting,
  running,
  suspending,
  suspendingImminent,
  hibernating,
  hibernatingImminent,
  unknown;

  static ScooterPowerState fromString(String? powerState) {
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
      default:
        log("Unknown state: $powerState");
        return ScooterPowerState.unknown;
    }
  }
}