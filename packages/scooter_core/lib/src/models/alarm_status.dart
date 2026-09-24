import 'package:logging/logging.dart';

enum AlarmStatus {
  disabled,
  disarmed,
  delayArmed,
  armed,
  level1Triggered,
  level2Triggered,
  seatboxAccess,
  unknown;

  static AlarmStatus? fromString(String? status) {
    final log = Logger("AlarmStatus");

    switch (status) {
      case "disabled":
        return AlarmStatus.disabled;
      case "disarmed":
        return AlarmStatus.disarmed;
      case "delay-armed":
        return AlarmStatus.delayArmed;
      case "armed":
        return AlarmStatus.armed;
      case "level-1-triggered":
        return AlarmStatus.level1Triggered;
      case "level-2-triggered":
        return AlarmStatus.level2Triggered;
      case "seatbox-access":
        return AlarmStatus.seatboxAccess;
      case null:
        return null;
      default:
        log.warning("Unknown status: $status");
        return AlarmStatus.unknown;
    }
  }
}
