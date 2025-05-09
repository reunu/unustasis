import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/background/translate_static.dart';

import '../background/bg_service.dart';
import '../domain/scooter_state.dart';

// value cache
bool _connected = false;
DateTime? _lastPing;
String? _lastPingDifference;
ScooterState? _scooterState;
String? _stateName;
int? _primarySOC;
int? _secondarySOC;
String? _scooterName;
int? _scooterColor;
LatLng? _lastLocation;
bool? _seatClosed;

void passToWidget({
  bool connected = false,
  DateTime? lastPing,
  ScooterState? scooterState,
  int? primarySOC,
  int? secondarySOC,
  String? scooterName,
  int? scooterColor,
  LatLng? lastLocation,
  bool? seatClosed,
}) async {
  if (connected != _connected ||
      (scooterState?.isOn) != (_scooterState?.isOn) ||
      (scooterState?.isReadyForSeatOpen) !=
          (_scooterState?.isReadyForSeatOpen) ||
      lastPing?.calculateTimeDifferenceInShort() != _lastPingDifference ||
      getStateNameForWidget(scooterState) !=
          _stateName || //_scooterState || // th is state is ignored in the widget
      primarySOC != _primarySOC ||
      secondarySOC != _secondarySOC ||
      scooterName != _scooterName ||
      scooterColor != _scooterColor ||
      lastLocation != _lastLocation ||
      seatClosed != _seatClosed) {
    print("Relevant values have changed");
    print("Connected: $connected vs $_connected");
    print(
      "Last ping: ${lastPing?.calculateTimeDifferenceInShort()} vs ${_lastPing?.calculateTimeDifferenceInShort()}",
    );
    print("Scooter state: $scooterState vs $_scooterState");
    print("State name: ${getStateNameForWidget(scooterState)} vs $_stateName");
    print("Primary SOC: $primarySOC vs $_primarySOC");
    print("Secondary SOC: $secondarySOC vs $_secondarySOC");
    print("Scooter name: $scooterName vs $_scooterName");
    print("Scooter color: $scooterColor vs $_scooterColor");
    print("Last location: $lastLocation vs $_lastLocation");
    print("Seat closed: $seatClosed vs $_seatClosed");

    // update cached values
    _connected = connected;
    _lastPing = lastPing;
    _lastPingDifference = lastPing?.calculateTimeDifferenceInShort();
    _scooterState = scooterState;
    _stateName = getStateNameForWidget(scooterState);
    _primarySOC = primarySOC;
    _secondarySOC = secondarySOC;
    _scooterName = scooterName;
    _scooterColor = scooterColor;
    _lastLocation = lastLocation;
    _seatClosed = seatClosed;

    await HomeWidget.saveWidgetData<bool>("connected", connected);
    if (scooterState != null) {
      await HomeWidget.saveWidgetData<bool>("locked", !scooterState.isOn);
      await HomeWidget.saveWidgetData<bool>(
        "seatOpenable",
        scooterState.isReadyForSeatOpen,
      );
    }

    // Not broadcasting "linking" state by default
    await HomeWidget.saveWidgetData<String>("stateName", _stateName);

    await HomeWidget.saveWidgetData<String?>(
      "lastPing",
      _lastPingDifference,
    );

    await HomeWidget.saveWidgetData<int>("soc1", primarySOC);
    await HomeWidget.saveWidgetData<int?>("soc2", secondarySOC);
    await HomeWidget.saveWidgetData<String>("scooterName", scooterName);
    await HomeWidget.saveWidgetData<int>("scooterColor", scooterColor);
    await HomeWidget.saveWidgetData("seatClosed", seatClosed);

    await HomeWidget.saveWidgetData<String>(
      "lastLat",
      lastLocation?.latitude.toString() ?? "0.0",
    );
    await HomeWidget.saveWidgetData<String>(
      "lastLon",
      lastLocation?.longitude.toString() ?? "0.0",
    );

    // once everything is set, rebuild the widget
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
    );
  } else {
    print("No relevant changes");
  }
}

String? getStateNameForWidget(ScooterState? state) {
  if (state == ScooterState.linking) {
    return ScooterState.disconnected.getNameStatic();
  } else {
    return state.getNameStatic();
  }
}

Future<void> setWidgetScanning(bool scanning) async {
  await HomeWidget.saveWidgetData<bool>("scanning", scanning);
  await HomeWidget.saveWidgetData<String>(
    "stateName",
    scanning
        ? ScooterState.linking.getNameStatic()
        : ScooterState.disconnected.getNameStatic(),
  );

  _stateName = scanning
      ? ScooterState.linking.getNameStatic()
      : ScooterState.disconnected.getNameStatic();
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

@pragma("vm:entry-point")
FutureOr<void> backgroundCallback(Uri? data) async {
  await HomeWidget.setAppGroupId('de.freal.unustasis');
  print("Unu widget received data: $data");
  if (await FlutterBackgroundService().isRunning() == false) {
    final service = FlutterBackgroundService();
    await service.startService();
  }
  switch (data?.host) {
    case "scan":
      setWidgetScanning(true);
      if (!backgroundScanEnabled) {
        FlutterBackgroundService().invoke("unlock");
      }
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
  String? calculateTimeDifferenceInShort() {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '${(difference.inDays / 7).floor()}w';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m';
    } else {
      return null;
    }
  }
}
