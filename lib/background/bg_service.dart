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
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';
import '../background/notification_handler.dart';

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;
ServiceInstance? _serviceInstance;

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
      initialNotificationContent: 'Starting background service...',
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

Future<void> _updateServiceMode(bool isForeground) async {
  if (_serviceInstance is AndroidServiceInstance) {
    final androidService = _serviceInstance as AndroidServiceInstance;
    if (isForeground) {
      await androidService.setAsForegroundService();
    } else {
      await androidService.setAsBackgroundService();
    }
  }
}

void _enableScanning() async {
  backgroundScanEnabled = true;
  _rescanTimer?.start();
  scooterService.rssiTimer.start();

  final savedScooters = await scooterService.getSavedScooterIds(onlyAutoConnect: true);
  if (savedScooters.isNotEmpty) {
    await _updateServiceMode(true);
    updateNotification();
    attemptConnectionCycle();
  } else {
    Logger("bgservice").info("No saved scooters, not showing notification");
    await _updateServiceMode(false);
    dismissNotification();
  }
}

void _disableScanning() async {
  Logger("bgservice").info("Disabling background scanning");
  backgroundScanEnabled = false;
  _rescanTimer
    ?..pause()
    ..reset();
  scooterService.rssiTimer.pause();
  Logger("bgservice").info("Setting service as background service");
  await _updateServiceMode(false);
  Logger("bgservice").info("Service set as background, dismissing notification");
  dismissNotification();
  Logger("bgservice").info("Background scanning disabled, notification dismissed");
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  _serviceInstance = service;
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
        Logger("bgservice").info("Received backgroundScan update: ${data!["backgroundScan"]}, current state: $backgroundScanEnabled");
        if (data["backgroundScan"] == false && backgroundScanEnabled) {
          // was true, now is false. Shut it down!
          Logger("bgservice").info("Toggling background scan from ON to OFF");
          _disableScanning();
        } else if (data["backgroundScan"] == true && !backgroundScanEnabled) {
          // was false, now is true. Start it up!
          Logger("bgservice").info("Toggling background scan from OFF to ON");
          _enableScanning();
        } else {
          Logger("bgservice").info("Background scan state unchanged: ${data["backgroundScan"]}");
        }
      }
      if (data?["updateSavedScooters"] == true) {
        await scooterService.refetchSavedScooters();
        if (backgroundScanEnabled) {
          Logger("bgservice").info("Scooters updated, re-evaluating scanning state.");
          _enableScanning();
        }
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
      await scooterService.lock(checkHandlebars: false);
      Future.delayed(const Duration(seconds: 3), () {
        setWidgetUnlocking(false);
      });
    } else {
      // scan first, then lock
      setWidgetScanning(true);
      await attemptConnectionCycle();
      setWidgetScanning(false);
      if (scooterService.connected) {
        setWidgetUnlocking(true);
        await scooterService.lock(checkHandlebars: false);
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
      await scooterService.unlock(checkHandlebars: false);
      Future.delayed(const Duration(seconds: 3), () {
        setWidgetUnlocking(false);
      });
    } else {
      // scan first, then unlock
      setWidgetScanning(true);
      await attemptConnectionCycle();
      setWidgetScanning(false);
      if (scooterService.connected) {
        setWidgetUnlocking(true);
        await scooterService.unlock(checkHandlebars: false);
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
