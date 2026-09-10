import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
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

extension AlarmStatusExtension on AlarmStatus {
  String name(BuildContext context) {
    switch (this) {
      case AlarmStatus.disabled:
        return FlutterI18n.translate(context, "alarm_status_disabled");
      case AlarmStatus.disarmed:
        return FlutterI18n.translate(context, "alarm_status_disarmed");
      case AlarmStatus.delayArmed:
        return FlutterI18n.translate(context, "alarm_status_delay_armed");
      case AlarmStatus.armed:
        return FlutterI18n.translate(context, "alarm_status_armed");
      case AlarmStatus.level1Triggered:
        return FlutterI18n.translate(context, "alarm_status_level_1_triggered");
      case AlarmStatus.level2Triggered:
        return FlutterI18n.translate(context, "alarm_status_level_2_triggered");
      case AlarmStatus.seatboxAccess:
        return FlutterI18n.translate(context, "alarm_status_seatbox_access");
      case AlarmStatus.unknown:
        return FlutterI18n.translate(context, "alarm_status_unknown");
    }
  }
}
