import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/widget_handler.dart';
import '../domain/statistics_helper.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';
import '../background/notification_handler.dart';

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;

FlutterBluePlusMockable fbp = FlutterBluePlusMockable();
ScooterService scooterService = ScooterService(fbp, isInBackgroundService: true);

Future<void> setupBackgroundService() async {
  final log = Logger("setupBackgroundService");
  final service = FlutterBackgroundService();

  HomeWidget.registerInteractivityCallback(backgroundCallback);

  backgroundScanEnabled = (await SharedPreferences.getInstance()).getBool("backgroundScan") ?? false;
  log.info("Background scan: $backgroundScanEnabled");

  if (Platform.isAndroid) {
    await setupNotifications();
  }

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
      notificationChannelId: notificationChannelId, // this must match with notification channel you created above.
      initialNotificationTitle: 'Unu Scooter',
      initialNotificationContent: 'You can dismiss this notification.',
      foregroundServiceNotificationId: notificationId,
    ),
  );

  service.startService();

  if (!backgroundScanEnabled) {
    dismissNotification();
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // this will be updated occasionally by the system
  Logger("bgservice").info("Background service started on iOS!");
  // Ensure that the Flutter engine is initialized.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // Set up a scooter service instance.
  scooterService = ScooterService(fbp, isInBackgroundService: true);
  // Make sure scooterService has time to initialize all values
  await Future.delayed(const Duration(seconds: 5));
  // update the widget
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
void onStart(ServiceInstance service) async {
  Logger("bgservice").onRecord.listen((record) {
    // ignore: avoid_print
    print("[${record.level.name}] ${record.time}: ${record.message} ${record.error ?? ""} ${record.stackTrace ?? ""}");
  });
  Logger("bgservice").info("Background service started!");
  DartPluginRegistrant.ensureInitialized();

  backgroundScanEnabled = (await SharedPreferences.getInstance()).getBool("backgroundScan") ?? false;

  if (service is AndroidServiceInstance && await service.isForegroundService()) {
    if (backgroundScanEnabled) {
      Logger("bgservice").info("Running first connection cycle");
      _enableScanning();
    } else {
      Logger("bgservice").info("Dismissing initial notification");
      _disableScanning();
    }
  }

  Logger("bgservice").info("Seeding widget with initial data");
  // seed widget
  await HomeWidget.setAppGroupId("group.de.freal.unustasis");
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
  Logger("bgservice").info("Widget seeded with initial data. ScooterName: ${scooterService.scooterName}");

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
      if (data?["lastPingInt"] != null) {
        scooterService.lastPing = DateTime.fromMillisecondsSinceEpoch(data!["lastPingInt"]);
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
      if (data?["updateSavedScooters"] == true) {
        await scooterService.refetchSavedScooters();
      }

      Future.delayed(const Duration(seconds: 3), () {
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
      });
    } catch (e, stack) {
      Logger("bgservice").severe("Something bad happened on command: $e", e, stack);
    }
  });

  service.on("lock").listen((data) async {
    Logger("bgservice").info("Received lock command");
    if (scooterService.connected) {
      setWidgetUnlocking(true);
      await scooterService.lock(
        checkHandlebars: false,
        source: EventSource.background,
      );
      Future.delayed(const Duration(seconds: 3), () {
        setWidgetUnlocking(false);
      });
    } else {
      // scan first, then lock
      setWidgetScanning(true);
      await attemptConnectionCycle();
      setWidgetScanning(false);
      // try again after connection attempt was made
      if (scooterService.connected) {
        setWidgetUnlocking(true);
        await scooterService.lock(
          checkHandlebars: false,
          source: EventSource.background,
        );
        Future.delayed(const Duration(seconds: 3), () {
          setWidgetUnlocking(false);
        });
      }
    }
  });

  service.on("unlock").listen((data) async {
    Logger("bgservice").info("Received unlock command");
    if (scooterService.connected) {
      setWidgetUnlocking(true);
      await scooterService.unlock(
        checkHandlebars: false,
        source: EventSource.background,
      );
      Future.delayed(const Duration(seconds: 3), () {
        setWidgetUnlocking(false);
      });
    } else {
      // scan first, then unlock
      setWidgetScanning(true);
      await attemptConnectionCycle();
      setWidgetScanning(false);
      // try again after connection attempt was made
      if (scooterService.connected) {
        setWidgetUnlocking(true);
        await scooterService.unlock(
          checkHandlebars: false,
          source: EventSource.background,
        );
        Future.delayed(const Duration(seconds: 3), () {
          setWidgetUnlocking(false);
        });
      }
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
      setWidgetScanning(false);
      if (scooterService.connected) scooterService.openSeat();
    }
  });

  service.on("test").listen((data) async {
    Logger("bgservice").info("Test command received by background service! Data: $data");
  });

  // listen to changes
  scooterService.addListener(() async {
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
      scooterLocked: scooterService.handlebarsLocked,
    );
    if (backgroundScanEnabled) {
      updateNotification();
    }
  });

  _rescanTimer = PausableTimer.periodic(const Duration(seconds: 35), () async {
    if (!backgroundScanEnabled) {
      Logger("bgservice").info("Oh boy, the timer must've killed itself/been killed. Resetting!");
      _rescanTimer
        ?..pause()
        ..reset();
      return;
    }
    if (backgroundScanEnabled &&
        service is AndroidServiceInstance &&
        await service.isForegroundService() &&
        (await scooterService.getSavedScooterIds(onlyAutoConnect: true)).isNotEmpty &&
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
