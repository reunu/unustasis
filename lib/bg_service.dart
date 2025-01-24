import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

// Notification identifiers
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';
const notificationId = 1612;

FlutterBluePlusMockable fbp = FlutterBluePlusMockable();
ScooterService scooterService = ScooterService(fbp);

void startBackgroundService() {
  final service = FlutterBackgroundService();
  service.startService();
}

void stopBackgroundService() {
  final service = FlutterBackgroundService();
  service.invoke("stop");
}

void updateWidget() async {
  print("Updating widget");
  // update all data we have
  await HomeWidget.saveWidgetData<bool>("connected", scooterService.connected);
  await HomeWidget.saveWidgetData<int>("state", scooterService.state!.index);
  // Not broadcasting "linking" state by default
  await HomeWidget.saveWidgetData<String>(
      "stateName",
      scooterService.state == ScooterState.linking
          ? ScooterState.disconnected.getNameStatic()
          : scooterService.state?.getNameStatic());
  await HomeWidget.saveWidgetData<String>("lastPing",
      scooterService.lastPing?.calculateTimeDifferenceInShort() ?? "");
  await HomeWidget.saveWidgetData<int>("soc1", scooterService.primarySOC);
  await HomeWidget.saveWidgetData<int?>("soc2", scooterService.secondarySOC);
  await HomeWidget.saveWidgetData<String>(
      "scooterName", scooterService.scooterName);
  await HomeWidget.saveWidgetData<String>(
      "lastLat", scooterService.lastLocation?.latitude.toString() ?? "0.0");
  await HomeWidget.saveWidgetData<String>(
      "lastLon", scooterService.lastLocation?.longitude.toString() ?? "0.0");

// once all is set, rebuild the widget
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

Future<void> setupBackgroundService() async {
  final service = FlutterBackgroundService();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationChannelId, // id
          notificationChannelName, // title
          description:
              'This channel is used for periodically checking your scooter.', // description
          importance: Importance
              .low, // importance must be at low or higher levelongoing: true,
        ),
      );

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      autoStart: true,
      onStart: onStart,
      isForegroundMode: true,
      autoStartOnBoot: true,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
      notificationChannelId:
          notificationChannelId, // this must match with notification channel you created above.
      initialNotificationTitle: 'Unu Scooter',
      initialNotificationContent: 'Loading...',
      foregroundServiceNotificationId: notificationId,
    ),
  );

  HomeWidget.registerInteractivityCallback(backgroundCallback);
}

Future<void> setWidgetScanning(bool scanning) async {
  await HomeWidget.saveWidgetData<bool>("scanning", scanning);
  await HomeWidget.saveWidgetData<String>(
      "stateName", ScooterState.linking.getNameStatic());
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

void updateNotification({String? debugText}) async {
  FlutterLocalNotificationsPlugin().show(
    notificationId,
    "Unu Scooter",
    scooterService.state?.getNameStatic(),
    const NotificationDetails(
      android: AndroidNotificationDetails(
          notificationChannelId, notificationChannelName,
          icon: 'ic_bg_service_small',
          ongoing: true,
          importance: Importance.max,
          priority: Priority.high,
          autoCancel: false),
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma("vm:entry-point")
FutureOr<void> backgroundCallback(Uri? data) async {
  await HomeWidget.setAppGroupId('de.freal.unustasis');
  print("Received data: $data");
  String? scooterId = scooterService.getMostRecentScooter()?.id;
  print("Our scooter is $scooterId");
  switch (data?.host) {
    case "stop":
      stopBackgroundService();
    case "scan":
      setWidgetScanning(true);
    case "lock":
      ScooterService.sendStaticPowerCommand(scooterId!, "scooter:state lock");
    case "unlock":
      ScooterService.sendStaticPowerCommand(scooterId!, "scooter:state unlock");
    case "openseat":
      ScooterService.sendStaticPowerCommand(scooterId!, "scooter:seatbox open");
    case "ping":
      print("pong");
      scooterService.testPing();
      print("Replied from scooterService ${scooterService.serviceIdentifier}");
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

bool connected = false;
DateTime? lastPing;
ScooterState? state;
int? scooterColor;
int? primarySOC;
int? secondarySOC;
bool scanning = false;
String? scooterName;
LatLng? lastLocation;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print("Background service started!");

  if (service is AndroidServiceInstance &&
      await service.isForegroundService()) {
    await scooterService.attemptConnection();
    setWidgetScanning(false);
  }
  // listen to changes
  scooterService.addListener(() {
    print("ScooterService updated");
    if (connected != scooterService.connected ||
        lastPing != scooterService.lastPing ||
        state != scooterService.state ||
        scooterColor != scooterService.scooterColor ||
        primarySOC != scooterService.primarySOC ||
        secondarySOC != scooterService.secondarySOC ||
        scooterName != scooterService.scooterName ||
        scanning != scooterService.scanning ||
        lastLocation != scooterService.lastLocation) {
      print("Relevant values have changed");
      // update state values
      connected = scooterService.connected;
      lastPing = scooterService.lastPing;
      state = scooterService.state;
      scooterColor = scooterService.scooterColor;
      primarySOC = scooterService.primarySOC;
      secondarySOC = scooterService.secondarySOC;
      scanning = scooterService.scanning;
      scooterName = scooterService.scooterName;
      lastLocation = scooterService.lastLocation;
      // update home screen widget
      updateWidget();
      updateNotification();
    } else {
      print("No relevant values have changed");
    }

    // set up state values
    connected = scooterService.connected;
    lastPing = scooterService.lastPing;
    state = scooterService.state;
    scooterColor = scooterService.scooterColor;
    primarySOC = scooterService.primarySOC;
    secondarySOC = scooterService.secondarySOC;
    scanning = scooterService.scanning; // debug
    scooterName = scooterService.scooterName;
  });

  Timer.periodic(const Duration(seconds: 35), (timer) async {
    if (service is AndroidServiceInstance &&
        await service.isForegroundService() &&
        (await scooterService.getSavedScooterIds()).isNotEmpty &&
        !scooterService.scanning &&
        !scooterService.connected) {
      print("Attempting connection");
      try {
        await scooterService.attemptConnection();
        setWidgetScanning(false);
      } catch (e, stack) {
        print("Didn't connect");
      }
    }
  });
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
        case ScooterState.unknown:
        default:
          return "Unknown";
      }
    }
  }
}
