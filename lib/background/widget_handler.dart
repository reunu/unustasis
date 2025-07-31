import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:workmanager/workmanager.dart';

import '../background/translate_static.dart';
import '../background/bg_service.dart';
import '../domain/scooter_state.dart';

// value cache
bool _connected = false;
DateTime? _lastPing;
String? _lastPingDifference;
String? _iOSlastPingText;
ScooterState? _scooterState;
String? _stateName;
int? _primarySOC;
int? _secondarySOC;
String? _scooterName;
int? _scooterColor;
LatLng? _lastLocation;
bool? _seatClosed;
bool? _scooterLocked = true;
String _lockStateName = "Unknown";

void setupWidget() {
  HomeWidget.setAppGroupId('group.de.freal.unustasis');
  HomeWidget.registerInteractivityCallback(backgroundCallback);
  setupWidgetTasks();
}

String widgetTaskID = "de.freal.unustasis.widget_refresh";

Future<void> setupWidgetTasks() async {
  Workmanager().initialize(workmanagerCallback, isInDebugMode: true);

  Workmanager().registerPeriodicTask(
    widgetTaskID,
    widgetTaskID,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    frequency: Duration(minutes: 2),
    initialDelay: Duration(minutes: 1),
  );
  print("Widget tasks initialized with workmanager ID: $widgetTaskID");
}

@pragma('vm:entry-point')
void workmanagerCallback() {
  Workmanager().executeTask((task, inputData) async {
    print("Workmanager task executing: $task");
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task == widgetTaskID) {
      await updateWidgetPing();
    }
    // Return true to indicate success to Workmanager.
    return true;
  });
}

Future<void> updateWidgetPing() async {
  HomeWidget.setAppGroupId('group.de.freal.unustasis');
  if (_lastPing != null) {
    // just use the cached ping
    _lastPingDifference = _lastPing?.calculateTimeDifferenceInShort();
    _iOSlastPingText = getLocalizedTimeDiff(_lastPing);
  } else {
    // get the last ping from widget data
    int? lastPingInt = await HomeWidget.getWidgetData<int?>("lastPing");
    if (lastPingInt != null) {
      _lastPing = DateTime.fromMillisecondsSinceEpoch(lastPingInt);
      _lastPingDifference = _lastPing?.calculateTimeDifferenceInShort();
      _iOSlastPingText = getLocalizedTimeDiff(_lastPing);
    }
  }
  await HomeWidget.saveWidgetData<String?>(
    "lastPingDifference",
    _lastPingDifference,
  );
  await HomeWidget.saveWidgetData<String>(
    "iOSlastPingText",
    _iOSlastPingText,
  );
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
    iOSName: "ScooterWidget",
  );
  return;
}

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
  bool? scooterLocked,
}) async {
  HomeWidget.setAppGroupId('group.de.freal.unustasis');
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
      seatClosed != _seatClosed ||
      scooterLocked != _scooterLocked) {
    // update cached values
    _connected = connected;
    _lastPing = lastPing;
    _lastPingDifference = lastPing?.calculateTimeDifferenceInShort();
    _iOSlastPingText = getLocalizedTimeDiff(lastPing);
    _scooterState = scooterState;
    _stateName = getStateNameForWidget(scooterState);
    _primarySOC = primarySOC;
    _secondarySOC = secondarySOC;
    _scooterName = scooterName;
    _scooterColor = scooterColor;
    _lastLocation = lastLocation;
    _seatClosed = seatClosed;
    _scooterLocked = scooterLocked;
    _lockStateName = getLocalizedLockStateName(scooterLocked ?? true);

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

    await HomeWidget.saveWidgetData<int?>(
      "lastPing",
      _lastPing?.millisecondsSinceEpoch,
    );

    await HomeWidget.saveWidgetData<String?>(
      "lastPingDifference",
      _lastPingDifference,
    );

    await HomeWidget.saveWidgetData<String>(
      "iOSlastPingText",
      _iOSlastPingText,
    );

    await HomeWidget.saveWidgetData<int>("soc1", primarySOC);
    await HomeWidget.saveWidgetData<int?>("soc2", secondarySOC);
    await HomeWidget.saveWidgetData<String>("scooterName", scooterName);
    await HomeWidget.saveWidgetData<int>("scooterColor", scooterColor);
    await HomeWidget.saveWidgetData("seatClosed", seatClosed);
    await HomeWidget.saveWidgetData<bool>(
        "scooterLocked", scooterLocked ?? true);
    await HomeWidget.saveWidgetData<String>("lockStateName", _lockStateName);

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
      iOSName: "ScooterWidget",
    );
  } else {
    // no relevant changes, no need to update
  }
}

String? getStateNameForWidget(ScooterState? state) {
  if (state == ScooterState.linking) {
    return ScooterState.disconnected.getNameStatic();
  } else {
    return state.getNameStatic();
  }
}

Future<void> setWidgetUnlocking(bool unlocking) async {
  await HomeWidget.saveWidgetData<bool>("scanning", unlocking);
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
    iOSName: "ScooterWidget",
  );
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
    iOSName: "ScooterWidget",
  );
}

@pragma("vm:entry-point")
FutureOr<void> backgroundCallback(Uri? data) async {
  print("Unu widget received data: $data");
  await HomeWidget.setAppGroupId('de.freal.unustasis');

  try {
    if (await FlutterBackgroundService().isRunning() == false) {
      final service = FlutterBackgroundService();
      await service.startService();
    }
  } catch (e) {
    print("Error starting background service: $e");
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
    default:
      print("Unknown command: ${data?.host}");
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
    iOSName: "ScooterWidget",
  );
}

extension DateTimeExtension on DateTime {
  String? calculateTimeDifferenceInShort() {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if (difference.inDays >= 1) {
      return '${difference.inDays}d';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h';
    } else {
      return null;
    }
  }
}
