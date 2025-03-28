import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';

// Notification identifiers
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';
const notificationId = 1612;

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;

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

  backgroundScanEnabled =
      (await SharedPreferences.getInstance()).getBool("backgroundScan") ?? true;
  print("Background scan: $backgroundScanEnabled");

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
  if (!backgroundScanEnabled) {
    dismissNotification();
  } else {
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
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

Future<void> attemptConnectionCycle() async {
  await scooterService.attemptLatestAutoConnection();
  setWidgetScanning(false);
  return;
}

void _enableScanning() {
  backgroundScanEnabled = true;
  _rescanTimer?.start();
  scooterService.rssiTimer.start();
  updateNotification();
  attemptConnectionCycle();
}

void _disableScanning() async {
  backgroundScanEnabled = false;
  _rescanTimer
    ?..pause()
    ..reset();
  scooterService.rssiTimer.pause();
  dismissNotification();
}

void dismissNotification() async {
  FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  await notifications.initialize(const InitializationSettings(
    android: AndroidInitializationSettings("ic_bg_service_small"),
  ));
  await notifications.show(
      notificationId,
      "Unu Scooter",
      (PlatformDispatcher.instance.locale.languageCode == "de")
          ? "Hintergrundverbindung deaktiviert. Du kannst diese Benachrichtigung schließen."
          : "Background service disabled. You can close this notification.",
      const NotificationDetails(
          android: AndroidNotificationDetails(
        notificationChannelId,
        notificationChannelName,
      )));
  await notifications.cancel(notificationId);
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print("Background service started!");
  DartPluginRegistrant.ensureInitialized();

  backgroundScanEnabled =
      (await SharedPreferences.getInstance()).getBool("backgroundScan") ?? true;

  if (service is AndroidServiceInstance &&
      await service.isForegroundService()) {
    if (backgroundScanEnabled) {
      print("Running first connection cycle");
      _enableScanning();
    } else {
      print("Dismissing initial notification");
      dismissNotification();
      _disableScanning();
    }
  }

  // seed widget
  print("Seeding: Most recent scooter is ${scooterService.scooterName}");
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

  service.on("autoUnlockCooldown").listen((data) async {
    print("Received autoUnlockCooldown command");
    scooterService.autoUnlockCooldown();
  });

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
      if (data?["backgroundScan"] != null) {
        if (data!["backgroundScan"] == false && backgroundScanEnabled) {
          // was true, now is false. Shut it down!
          _disableScanning();
        } else if (data["backgroundScan"] == true && !backgroundScanEnabled) {
          // was false, now is true. Start it up!
          _enableScanning();
        }
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
    if (scooterService.connected) {
      scooterService.unlock();
    } else {
      // scan first, then unlock
      setWidgetScanning(true);
      await attemptConnectionCycle();
      if (scooterService.connected) scooterService.unlock();
    }
  });

  service.on("openseat").listen((data) async {
    print("Received openseat command");
    scooterService.openSeat();
  });

  // listen to changes
  scooterService.addListener(() async {
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
    if (backgroundScanEnabled) {
      updateNotification();
    }
  });

  _rescanTimer = PausableTimer.periodic(const Duration(seconds: 35), () async {
    if (!backgroundScanEnabled) {
      print("Timer killed itself");
      _rescanTimer
        ?..pause()
        ..reset();
      dismissNotification();
      return;
    }
    if (backgroundScanEnabled &&
        service is AndroidServiceInstance &&
        await service.isForegroundService() &&
        (await scooterService.getSavedScooterIds()).isNotEmpty &&
        !scooterService.scanning &&
        !scooterService.connected) {
      attemptConnectionCycle();
    } else {
      print("Some conditions not met");
    }
  });

  _rescanTimer!.start();
}
