/// The alarm action a given state should offer the user.
enum AlarmAction { arm, disarm, stop }

/// Maps sunshine's `alarm_state` onto the single action worth offering.
///
/// Returns null for `disabled` (the alarm system is off, nothing to do from
/// here) and for anything sunshine grows later that we don't recognise.
AlarmAction? alarmActionFor(String? alarmState) {
  switch (alarmState) {
    case 'armed':
    case 'delay-armed':
      return AlarmAction.disarm;
    case 'disarmed':
    case 'seatbox-access':
      return AlarmAction.arm;
    case 'level-1-triggered':
    case 'level-2-triggered':
      return AlarmAction.stop;
    default:
      return null;
  }
}

/// i18n key naming the alarm state for display.
String alarmStateI18nKey(String? alarmState) {
  switch (alarmState) {
    case 'armed':
      return 'alarm_state_armed';
    case 'delay-armed':
      return 'alarm_state_delay_armed';
    case 'disarmed':
      return 'alarm_state_disarmed';
    case 'seatbox-access':
      return 'alarm_state_seatbox_access';
    case 'level-1-triggered':
      return 'alarm_state_triggered_l1';
    case 'level-2-triggered':
      return 'alarm_state_triggered_l2';
    case 'disabled':
      return 'alarm_state_disabled';
    default:
      return 'alarm_state_unknown';
  }
}
