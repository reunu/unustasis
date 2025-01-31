import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';

import '../background/widget_handler.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';

// Notification identifiers
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';
const notificationId = 1612;

FlutterBluePlusMockable fbp = FlutterBluePlusMockable();
ScooterService scooterService =
    ScooterService(fbp, isInBackgroundService: true);

startBackgroundService() {
  final service = FlutterBackgroundService();
  service.startService();
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

void attemptConnectionCycle() async {
  await scooterService.attemptLatestAutoConnection();
  setWidgetScanning(false);
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print("Background service started!");
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance &&
      await service.isForegroundService()) {
    attemptConnectionCycle();
  }

  // listen for commands
  service.on('update').listen((data) async {
    print("Received update command: $data");
    try {
      if (data?["autoUnlock"] != null) {
        scooterService.setAutoUnlock(data!["autoUnlock"]);
      }
      if (data?["autoUnlockThreshold"] != null) {
        scooterService.setAutoUnlockThreshold(data!["autoUnlockThreshold"]);
      }
      if (data?["openSeatOnUnlock"] != null) {
        scooterService.setOpenSeatOnUnlock(data!["openSeatOnUnlock"]);
      }
      if (data?["hazardLocking"] != null) {
        scooterService.setHazardLocking(data!["hazardLocking"]);
      }
      if (data?["scooterName"] != null) {
        scooterService.scooterName = data!["scooterName"];
      }
      if (data?["mostRecent"] != null) {
        scooterService.setMostRecentScooter(data!["mostRecent"]);
      }
      if (data?["lastPing"] != null) {
        scooterService.lastPing = data!["lastPing"];
      }
    } catch (e) {
      print("Somethin happen");
    }
  });

  service.on("lock").listen((data) async {
    print("Received lock command");
    scooterService.lock();
  });

  service.on("unlock").listen((data) async {
    print("Received unlock command");
    scooterService.unlock();
  });

  service.on("openseat").listen((data) async {
    print("Received openseat command");
    scooterService.openSeat();
  });

  // listen to changes
  scooterService.addListener(() {
    print("ScooterService updated");
    passToWidget(
      connected: scooterService.connected,
      lastPing: scooterService.lastPing,
      scooterState: scooterService.state,
      primarySOC: scooterService.primarySOC,
      secondarySOC: scooterService.secondarySOC,
      scooterName: scooterService.scooterName,
      lastLocation: scooterService.lastLocation,
      seatClosed: scooterService.seatClosed,
    );
    updateNotification();
  });

  Timer.periodic(const Duration(seconds: 35), (timer) async {
    if (service is AndroidServiceInstance &&
        await service.isForegroundService() &&
        (await scooterService.getSavedScooterIds()).isNotEmpty &&
        !scooterService.scanning &&
        !scooterService.connected) {
      attemptConnectionCycle();
    }
  });
}
