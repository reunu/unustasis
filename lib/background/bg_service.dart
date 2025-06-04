import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../background/widget_handler.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';
import '../background/notification_handler.dart';

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;

FlutterBluePlusMockable fbp = FlutterBluePlusMockable();
ScooterService scooterService =
    ScooterService(fbp, isInBackgroundService: true);

Future<void> setupWidgetTasks() async {
  Workmanager().initialize(workmanagerCallback, isInDebugMode: false);

  Workmanager().registerPeriodicTask(
    "hourly-updater",
    "updateWidget",
    existingWorkPolicy: ExistingWorkPolicy.replace,
    frequency: Duration(hours: 1),
    initialDelay: Duration(minutes: 1),
  );
}

Future<void> setupBackgroundService() async {
  final log = Logger("setupBackgroundService");
  final service = FlutterBackgroundService();

  backgroundScanEnabled =
      (await SharedPreferences.getInstance()).getBool("backgroundScan") ??
          false;
  log.info("Background scan: $backgroundScanEnabled");

  await setupNotifications();

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
      initialNotificationContent: 'You can dismiss this notification.',
      foregroundServiceNotificationId: notificationId,
    ),
  );

  HomeWidget.registerInteractivityCallback(backgroundCallback);

  await setupWidgetTasks();

  if (!backgroundScanEnabled) {
    dismissNotification();
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
}

@pragma('vm:entry-point')
void workmanagerCallback() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task == "updateWidget") {
      await updateWidgetPing();
    }
    // Return true to indicate success to Workmanager.
    return true;
  });
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Logger("bgservice").info("Background service started!");
  DartPluginRegistrant.ensureInitialized();

  backgroundScanEnabled =
      (await SharedPreferences.getInstance()).getBool("backgroundScan") ??
          false;

  if (service is AndroidServiceInstance &&
      await service.isForegroundService()) {
    if (backgroundScanEnabled) {
      Logger("bgservice").info("Running first connection cycle");
      _enableScanning();
    } else {
      Logger("bgservice").info("Dismissing initial notification");
      _disableScanning();
    }
  }

  // seed widget
  Future.delayed(const Duration(seconds: 5), () {
    passToWidget(
        connected: scooterService.connected,
        lastPing: scooterService.lastPing,
        scooterState: scooterService.state,
        primarySOC: scooterService.primarySOC,
        secondarySOC: scooterService.secondarySOC,
        scooterName: scooterService.scooterName,
        scooterColor: scooterService.scooterColor,
        lastLocation: scooterService.lastLocation,
        seatClosed: scooterService.seatClosed);
  });

  service.on("autoUnlockCooldown").listen((data) async {
    Logger("bgservice").info("Received autoUnlockCooldown command");
    scooterService.autoUnlockCooldown();
  });

  // listen for commands
  service.on("update").listen((data) async {
    Logger("bgservice").info("Received update command: $data");
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
      if (data?["scooterColor"] != null) {
        scooterService.scooterColor = data!["scooterColor"];
      }
      if (data?["mostRecent"] != null) {
        scooterService.setMostRecentScooter(data!["mostRecent"]);
      }
      if (data?["lastPingInt"] != null) {
        scooterService.lastPing =
            DateTime.fromMillisecondsSinceEpoch(data!["lastPingInt"]);
      }
      if (data?["backgroundScan"] != null) {
        if (data!["backgroundScan"] == false && backgroundScanEnabled) {
          // was true, now is false. Shut it down!
          _disableScanning();
        } else if (data["backgroundScan"] == true && !backgroundScanEnabled) {
          // was false, now is true. Start it up!
          Logger("bgservice").info("Enabling BG scanning");
          _enableScanning();
        }
      }
      if (data?["forgetSavedScooter"] != null) {
        scooterService.forgetSavedScooter(data!["id"]);
      }
      if (data?["addSavedScooter"] != null) {
        scooterService.addSavedScooter(data!["id"]);
      }

      passToWidget(
        connected: scooterService.connected,
        lastPing: scooterService.lastPing,
        scooterState: scooterService.state,
        primarySOC: scooterService.primarySOC,
        secondarySOC: scooterService.secondarySOC,
        scooterName: scooterService.scooterName,
        scooterColor: scooterService.scooterColor,
        lastLocation: scooterService.lastLocation,
        seatClosed: scooterService.seatClosed,
      );
    } catch (e, stack) {
      Logger("bgservice")
          .severe("Something bad happened on command: $e", e, stack);
    }
  });

  service.on("lock").listen((data) async {
    Logger("bgservice").info("Received lock command");
    scooterService.lock();
  });

  service.on("unlock").listen((data) async {
    Logger("bgservice").info("Received unlock command");
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
    Logger("bgservice").info("Received openseat command");
    if (scooterService.connected) {
      scooterService.openSeat();
    } else {
      // scan first, then open seat
      setWidgetScanning(true);
      await attemptConnectionCycle();
      if (scooterService.connected) scooterService.openSeat();
    }
  });

  // listen to changes
  scooterService.addListener(() async {
    Logger("bgservice").info("ScooterService updated");
    passToWidget(
      connected: scooterService.connected,
      lastPing: scooterService.lastPing,
      scooterState: scooterService.state,
      primarySOC: scooterService.primarySOC,
      secondarySOC: scooterService.secondarySOC,
      scooterName: scooterService.scooterName,
      scooterColor: scooterService.scooterColor,
      lastLocation: scooterService.lastLocation,
      seatClosed: scooterService.seatClosed,
    );
    if (backgroundScanEnabled) {
      updateNotification();
    }
  });

  _rescanTimer = PausableTimer.periodic(const Duration(seconds: 35), () async {
    if (!backgroundScanEnabled) {
      Logger("bgservice").info(
          "Oh boy, the timer must've killed itself/been killed. Resetting!");
      _rescanTimer
        ?..pause()
        ..reset();
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
      Logger("bgservice").info(
          "Some conditions for rescanning not met. backgroundScanEnabled: $backgroundScanEnabled, scooterService.scanning: ${scooterService.scanning}, scooterService.connected: ${scooterService.connected}");
    }
  });

  _rescanTimer!.start();
}
