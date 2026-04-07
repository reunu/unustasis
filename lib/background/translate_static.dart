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

/// Hardcoded English fallbacks so that raw i18n keys never leak to the widget
/// even when rootBundle fails to load translations in a background isolate.
const _englishFallbacks = {
  'state_name_off': 'Off',
  'state_name_standby': 'Standby',
  'state_name_parked': 'Parked',
  'state_name_ready': 'Ready',
  'state_name_updating': 'Updating',
  'state_name_waiting_seatbox': 'Close Seat',
  'state_name_waiting_hibernation': 'Hibernating…',
  'state_name_hibernating': 'Hibernating',
  'state_name_hibernating_imminent': 'Hibernating',
  'state_name_booting': 'Booting',
  'state_name_linking': 'Connecting…',
  'state_name_disconnected': 'Disconnected',
  'state_name_shutting_down': 'Shutting Down',
  'state_name_unknown': 'Unknown',
  'lock_state_locked': 'Locked',
  'lock_state_unlocked': 'Unlocked',
  'lock_state_unknown': '',
};

final _i18n = BackgroundI18n.instance;

extension ScooterStateName on ScooterState? {
  String getNameStatic() {
    final key = _stateKeys[this] ?? 'state_name_unknown';
    final translated = _i18n.translate(key);
    // If translate returned the raw key (i18n not loaded), use hardcoded fallback.
    return translated == key ? (_englishFallbacks[key] ?? translated) : translated;
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
  String safeTranslate(String key) {
    final translated = _i18n.translate(key);
    return translated == key ? (_englishFallbacks[key] ?? translated) : translated;
  }

  switch (locked) {
    case true:
      return safeTranslate('lock_state_locked');
    case false:
      return safeTranslate('lock_state_unlocked');
    default:
      return safeTranslate('lock_state_unknown');
  }
}
