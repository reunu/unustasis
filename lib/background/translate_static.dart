import 'dart:ui';

import '../background/widget_handler.dart';
import '../domain/scooter_state.dart';

extension ScooterStateName on ScooterState? {
  String getNameStatic({String? languageCode}) {
    String lang =
        languageCode ?? PlatformDispatcher.instance.locale.languageCode;

    if (lang == "de") {
      switch (this) {
        case ScooterState.off:
          return "Aus";
        case ScooterState.standby:
          return "Standby";
        case ScooterState.parked:
          return "Geparkt";
        case ScooterState.ready:
          return "Bereit";
        case ScooterState.hibernating:
          return "Tiefschlaf";
        case ScooterState.hibernatingImminent:
          return "Schläft bald...";
        case ScooterState.booting:
          return "Fährt hoch...";
        case ScooterState.linking:
          return "Suche...";
        case ScooterState.disconnected:
          return "Getrennt";
        case ScooterState.shuttingDown:
          return "Herunterfahren...";
        case ScooterState.unknown:
        default:
          return "Unbekannt";
      }
    } else {
      switch (this) {
        case ScooterState.off:
          return "Off";
        case ScooterState.standby:
          return "Stand-by";
        case ScooterState.parked:
          return "Parked";
        case ScooterState.ready:
          return "Ready";
        case ScooterState.hibernating:
          return "Hibernating";
        case ScooterState.hibernatingImminent:
          return "Hibernating soon...";
        case ScooterState.booting:
          return "Booting...";
        case ScooterState.linking:
          return "Searching...";
        case ScooterState.disconnected:
          return "Disconnected";
        case ScooterState.shuttingDown:
          return "Shutting down...";
        case ScooterState.unknown:
        default:
          return "Unknown";
      }
    }
  }
}

String getLocalizedNotificationAction(String actionId) {
  String lang = PlatformDispatcher.instance.locale.languageCode;

  if (lang == "de") {
    switch (actionId) {
      case "lock":
        return "Schließen";
      case "unlock":
        return "Öffnen";
      case "openseat":
        return "Sitz öffnen";
      default:
        return "FEHLER";
    }
  } else {
    switch (actionId) {
      case "lock":
        return "Lock";
      case "unlock":
        return "Unlock";
      case "openseat":
        return "Open seat";
      default:
        return "ERROR";
    }
  }
}

String? getLocalizedTimeDiff(DateTime? lastPing) {
  String lang = PlatformDispatcher.instance.locale.languageCode;

  if (lastPing == null) {
    return null;
  }

  String? timeDiff = lastPing.calculateTimeDifferenceInShort();

  if (lang == "de") {
    if (timeDiff == null) {
      return "Vor kurzem";
    } else if (timeDiff == "1d") {
      return "Gestern";
    } else if (timeDiff == "2d") {
      return "Vorgestern";
    }
    return "Vor $timeDiff";
  } else {
    if (timeDiff == null) {
      return "Just now";
    } else if (timeDiff == "1d") {
      return "Yesterday";
    }
    return "$timeDiff ago";
  }
}

String getLocalizedLockStateName(bool? locked) {
  String lang = PlatformDispatcher.instance.locale.languageCode;

  if (lang == "de") {
    switch (locked) {
      case true:
        return "Verriegelt";
      case false:
        return "Offen";
      default:
        return "Unbekannt";
    }
  } else {
    switch (locked) {
      case true:
        return "Locked";
      case false:
        return "Unlocked";
      default:
        return "Unknown";
    }
  }
}
