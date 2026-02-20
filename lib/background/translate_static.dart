import 'dart:ui';

import '../background/widget_handler.dart';
import '../domain/scooter_state.dart';

extension ScooterStateName on ScooterState? {
  String getNameStatic({String? languageCode}) {
    String lang = languageCode ?? PlatformDispatcher.instance.locale.languageCode;

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
        case ScooterState.updating:
          return "Wird aktualisiert";
        case ScooterState.waitingSeatbox:
          return "Warte auf Sitzbox";
        case ScooterState.waitingHibernation:
        case ScooterState.waitingHibernationAdvanced:
        case ScooterState.waitingHibernationSeatbox:
        case ScooterState.waitingHibernationConfirm:
          return "Manueller Ruhezustand startet";
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
    } else if (lang == "fr") {
      switch (this) {
        case ScooterState.off:
          return "Éteint";
        case ScooterState.standby:
          return "Veille";
        case ScooterState.parked:
          return "Stationné";
        case ScooterState.ready:
          return "Prêt";
        case ScooterState.updating:
          return "Mise à jour";
        case ScooterState.waitingSeatbox:
          return "En attente du coffre";
        case ScooterState.waitingHibernation:
        case ScooterState.waitingHibernationAdvanced:
        case ScooterState.waitingHibernationSeatbox:
        case ScooterState.waitingHibernationConfirm:
          return "Hibernation manuelle en cours";
        case ScooterState.hibernating:
          return "En hibernation";
        case ScooterState.hibernatingImminent:
          return "Hibernation imminente...";
        case ScooterState.booting:
          return "Démarrage...";
        case ScooterState.linking:
          return "Recherche...";
        case ScooterState.disconnected:
          return "Déconnecté";
        case ScooterState.shuttingDown:
          return "Arrêt en cours...";
        case ScooterState.unknown:
        default:
          return "Inconnu";
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
        case ScooterState.updating:
          return "Updating";
        case ScooterState.waitingSeatbox:
          return "Waiting on Seatbox";
        case ScooterState.waitingHibernation:
        case ScooterState.waitingHibernationAdvanced:
        case ScooterState.waitingHibernationSeatbox:
        case ScooterState.waitingHibernationConfirm:
          return "Manual hibernation starting";
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
  } else if (lang == "fr") {
    switch (actionId) {
      case "lock":
        return "Verrouiller";
      case "unlock":
        return "Déverrouiller";
      case "openseat":
        return "Ouvrir la selle";
      default:
        return "ERREUR";
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
  } else if (lang == "fr") {
    if (timeDiff == null) {
      return "À l'instant";
    } else if (timeDiff == "1d") {
      return "Hier";
    } else if (timeDiff == "2d") {
      return "Avant-hier";
    }
    return "Il y a $timeDiff";
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
  } else if (lang == "fr") {
    switch (locked) {
      case true:
        return "Verrouillé";
      case false:
        return "Déverrouillé";
      default:
        return "Inconnu";
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
