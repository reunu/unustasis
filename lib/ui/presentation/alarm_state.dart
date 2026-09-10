import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';

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
