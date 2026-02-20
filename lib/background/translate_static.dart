import '../background/background_i18n.dart';
import '../background/widget_handler.dart';
import '../domain/scooter_state.dart';

const _stateKeys = {
  ScooterState.off: 'state_name_off',
  ScooterState.standby: 'state_name_standby',
  ScooterState.parked: 'state_name_parked',
  ScooterState.ready: 'state_name_ready',
  ScooterState.updating: 'state_name_updating',
  ScooterState.waitingSeatbox: 'state_name_waiting_seatbox',
  ScooterState.waitingHibernation: 'state_name_waiting_hibernation',
  ScooterState.waitingHibernationAdvanced: 'state_name_waiting_hibernation',
  ScooterState.waitingHibernationSeatbox: 'state_name_waiting_hibernation',
  ScooterState.waitingHibernationConfirm: 'state_name_waiting_hibernation',
  ScooterState.hibernating: 'state_name_hibernating',
  ScooterState.hibernatingImminent: 'state_name_hibernating_imminent',
  ScooterState.booting: 'state_name_booting',
  ScooterState.linking: 'state_name_linking',
  ScooterState.disconnected: 'state_name_disconnected',
  ScooterState.shuttingDown: 'state_name_shutting_down',
  ScooterState.unknown: 'state_name_unknown',
};

const _actionKeys = {
  'lock': 'controls_lock',
  'unlock': 'controls_unlock',
  'openseat': 'home_seat_button_closed',
};

final _i18n = BackgroundI18n.instance;

extension ScooterStateName on ScooterState? {
  String getNameStatic() {
    final key = _stateKeys[this] ?? 'state_name_unknown';
    return _i18n.translate(key);
  }
}

String getLocalizedNotificationAction(String actionId) {
  final key = _actionKeys[actionId];
  return key != null ? _i18n.translate(key) : _i18n.translate('error_generic');
}

String? getLocalizedTimeDiff(DateTime? lastPing) {
  if (lastPing == null) return null;

  String? timeDiff = lastPing.calculateTimeDifferenceInShort();

  if (timeDiff == null) {
    return _i18n.translate('time_just_now');
  } else if (timeDiff == '1d') {
    return _i18n.translate('time_yesterday');
  } else if (timeDiff == '2d') {
    return _i18n.translate('time_day_before_yesterday');
  }
  return _i18n.translate('time_ago').replaceAll('{time}', timeDiff);
}

String getLocalizedLockStateName(bool? locked) {
  switch (locked) {
    case true:
      return _i18n.translate('lock_state_locked');
    case false:
      return _i18n.translate('lock_state_unlocked');
    default:
      return _i18n.translate('lock_state_unknown');
  }
}
