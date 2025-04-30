import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../background/bg_service.dart';
import '../domain/scooter_state.dart';

// value cache
bool _connected = false;
DateTime? _lastPing;
ScooterState? _scooterState;
int? _primarySOC;
int? _secondarySOC;
String? _scooterName;
LatLng? _lastLocation;
bool? _seatClosed;

Logger log = Logger("WidgetHandler");

void passToWidget({
  bool connected = false,
  DateTime? lastPing,
  ScooterState? scooterState,
  int? primarySOC,
  int? secondarySOC,
  String? scooterName,
  LatLng? lastLocation,
  bool? seatClosed,
}) async {
  if (connected != _connected ||
      (scooterState?.isOn) != (_scooterState?.isOn) ||
      (scooterState?.isReadyForSeatOpen) !=
          (_scooterState?.isReadyForSeatOpen) ||
      lastPing?.calculateTimeDifferenceInShort() !=
          _lastPing?.calculateTimeDifferenceInShort() ||
      scooterState.getNameStatic() != _scooterState.getNameStatic() ||
      primarySOC != _primarySOC ||
      secondarySOC != _secondarySOC ||
      scooterName != _scooterName ||
      lastLocation != _lastLocation ||
      seatClosed != _seatClosed) {
    log.fine("Relevant values have changed");

    await HomeWidget.saveWidgetData<bool>("connected", connected);
    if (scooterState != null) {
      await HomeWidget.saveWidgetData<bool>("locked", !scooterState.isOn);
      await HomeWidget.saveWidgetData<bool>(
          "seatOpenable", scooterState.isReadyForSeatOpen);
    }

    // Not broadcasting "linking" state by default
    await HomeWidget.saveWidgetData<String>(
        "stateName",
        scooterService.state == ScooterState.linking
            ? ScooterState.disconnected.getNameStatic()
            : scooterService.state?.getNameStatic());

    await HomeWidget.saveWidgetData<String>(
        "lastPing", lastPing?.calculateTimeDifferenceInShort() ?? "");

    await HomeWidget.saveWidgetData<int>("soc1", primarySOC);
    await HomeWidget.saveWidgetData<int?>("soc2", secondarySOC);
    await HomeWidget.saveWidgetData<String>("scooterName", scooterName);
    await HomeWidget.saveWidgetData("seatClosed", seatClosed);

    await HomeWidget.saveWidgetData<String>(
        "lastLat", lastLocation?.latitude.toString() ?? "0.0");
    await HomeWidget.saveWidgetData<String>(
        "lastLon", lastLocation?.longitude.toString() ?? "0.0");

    // once everything is set, rebuild the widget
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
    );
  } else {
    log.fine("No relevant changes");
  }
}

Future<void> setWidgetScanning(bool scanning) async {
  await HomeWidget.saveWidgetData<bool>("scanning", scanning);
  await HomeWidget.saveWidgetData<String>(
      "stateName", ScooterState.linking.getNameStatic());
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

@pragma("vm:entry-point")
FutureOr<void> backgroundCallback(Uri? data) async {
  await HomeWidget.setAppGroupId('de.freal.unustasis');
  log.info("Received data: $data");
  switch (data?.host) {
    case "scan":
      setWidgetScanning(true);
    case "lock":
      FlutterBackgroundService().invoke("lock");
    case "unlock":
      FlutterBackgroundService().invoke("unlock");
    case "openseat":
      FlutterBackgroundService().invoke("openseat");
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

extension DateTimeExtension on DateTime {
  String calculateTimeDifferenceInShort() {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '${(difference.inDays / 7).floor()}W';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}D';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}H';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}M';
    } else {
      return "";
    }
  }
}

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
