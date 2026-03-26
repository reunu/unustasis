import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:pausable_timer/pausable_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/background_i18n.dart';
import '../background/widget_handler.dart';
import '../domain/statistics_helper.dart';
import '../flutter/blue_plus_mockable.dart';
import '../scooter_service.dart';
import '../background/notification_handler.dart';

bool backgroundScanEnabled = true;
PausableTimer? _rescanTimer;
AndroidServiceInstance? _androidServiceInstance;
bool _widgetActionInProgress = false;
Timer? _foregroundDemoteTimer;
const Duration _foregroundTimeout = Duration(minutes: 15);

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
      isForegroundMode: true, // Must start as foreground so Android allows restarts from widget callbacks
      autoStartOnBoot: true,
      foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
      notificationChannelId: serviceChannelId, // silent channel for the mandatory foreground service notification
      initialNotificationTitle: 'Unu Scooter',
      initialNotificationContent: 'You can dismiss this notification.',
      foregroundServiceNotificationId: notificationId,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // this will be updated occasionally by the system
  Logger("bgservice").info("Background service started on iOS!");
  // Ensure that the Flutter engine is initialized.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await BackgroundI18n.instance.init();
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
    scooterId: scooterService.myScooter?.remoteId.toString(),
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
  _foregroundDemoteTimer?.cancel();
  _androidServiceInstance?.setAsForegroundService();
  _rescanTimer?.start();
  scooterService.rssiTimer.start();
  updateNotification();
  attemptConnectionCycle();
}

void _disableScanning() {
  backgroundScanEnabled = false;
  _rescanTimer
    ?..pause()
    ..reset();
  scooterService.rssiTimer.pause();
  demoteToBackground();
}

/// Checks SharedPreferences for a pending widget action that was persisted
/// but never executed (e.g. because invoke() was lost).  Called from the
/// scooterService listener and the rescan timer as a fallback.
Future<void> _checkPendingWidgetAction() async {
  if (_widgetActionInProgress) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // re-read from disk (action was written in another isolate)
    final pending = prefs.getBool("pendingWidgetAction") ?? false;
    final actionName = prefs.getString("pendingWidgetActionName");
    if (pending && actionName != null) {
      Logger("bgservice").info("Found lost pending widget action: $actionName");
      _executeAction(actionName);
    }
  } catch (e) {
    Logger("bgservice").warning("Error checking pending widget action", e);
  }
}

/// Connects to the scooter if needed, then performs the given action.
/// Handles foreground promotion, scanning UI, and post-action cleanup.
Future<void> _executeAction(String actionName) async {
  if (_widgetActionInProgress) return;
  _widgetActionInProgress = true;

  final log = Logger("bgservice");
  log.info("Executing action: $actionName");

  try {
    setWidgetScanning(true);
    promoteToForeground();

    // Clear the persisted pending action so the fallback check in the
    // connection listener / rescan timer won't re-execute it.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("pendingWidgetAction", false);
    await prefs.remove("pendingWidgetActionName");

    if (!scooterService.connected) {
      setWidgetScanning(true);
      await attemptConnectionCycle();
      // attemptConnectionCycle already calls setWidgetScanning(false)
    } else {
      setWidgetScanning(false);
    }

    switch (actionName) {
      case "lock":
        setWidgetUnlocking(true);
        await scooterService.lock(
          checkHandlebars: false,
          source: EventSource.background,
        );
        Future.delayed(const Duration(seconds: 3), () => setWidgetUnlocking(false));
      case "unlock":
        setWidgetUnlocking(true);
        await scooterService.unlock(
          checkHandlebars: false,
          source: EventSource.background,
        );
        Future.delayed(const Duration(seconds: 3), () => setWidgetUnlocking(false));
      case "openseat":
        scooterService.openSeat();
      default:
        log.warning("Unknown action: $actionName");
    }
  } catch (e, stack) {
    log.severe("Action '$actionName' failed", e, stack);
  } finally {
    _widgetActionInProgress = false;
    setWidgetScanning(false);
    setWidgetUnlocking(false);
  }
}

/// Temporarily promotes the Android service to foreground mode.
/// If [temporary] is true and background scanning is disabled,
/// the service will automatically demote back to background after [_foregroundTimeout].
void promoteToForeground({bool temporary = true}) {
  if (_androidServiceInstance == null) return;

  _foregroundDemoteTimer?.cancel();
  _androidServiceInstance!.setAsForegroundService();

  if (temporary && !backgroundScanEnabled) {
    _scheduleDemoteTimer();
  }
}

/// Schedules the foreground demotion timer.
/// If the scooter is still connected when it fires, restarts for another cycle.
void _scheduleDemoteTimer() {
  _foregroundDemoteTimer?.cancel();
  _foregroundDemoteTimer = Timer(_foregroundTimeout, () {
    if (scooterService.connected) {
      Logger("bgservice").info("Scooter still connected, extending foreground timeout");
      _scheduleDemoteTimer();
    } else {
      demoteToBackground();
    }
  });
}

/// Stops the Android service entirely to save battery.
/// Only stops if background scanning is disabled and no scooter is connected.
void demoteToBackground() {
  if (_androidServiceInstance == null || backgroundScanEnabled) return;
  if (scooterService.connected) {
    _scheduleDemoteTimer();
    return;
  }

  _foregroundDemoteTimer?.cancel();
  dismissNotification();
  _androidServiceInstance!.stopSelf();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Logger("bgservice").onRecord.listen((record) {
    // ignore: avoid_print
    print("[${record.level.name}] ${record.time}: ${record.message} ${record.error ?? ""} ${record.stackTrace ?? ""}");
  });
  Logger("bgservice").info("Background service started!");
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await BackgroundI18n.instance.init();

  // Localize notification channels and replace initial notification
  if (Platform.isAndroid && service is AndroidServiceInstance) {
    localizeNotificationChannels();
    service.setForegroundNotificationInfo(
      title: 'Unu Scooter',
      content: BackgroundI18n.instance.translate('notification_service_content'),
    );
  }

  backgroundScanEnabled = (await SharedPreferences.getInstance()).getBool("backgroundScan") ?? false;

  // Check if we were started by a widget action
  final prefs = await SharedPreferences.getInstance();
  final pendingWidgetAction = prefs.getBool("pendingWidgetAction") ?? false;
  final pendingActionName = prefs.getString("pendingWidgetActionName");
  if (pendingWidgetAction) {
    await prefs.setBool("pendingWidgetAction", false);
    await prefs.remove("pendingWidgetActionName");
  }

  // Seed widget caches and clear stale spinner BEFORE any code path
  // that might stop the service (e.g. _disableScanning → stopSelf).
  Logger("bgservice").info("Seeding widget with initial data");
  await HomeWidget.setAppGroupId("group.de.freal.unustasis");
  await seedCachesFromWidget();
  if (!pendingWidgetAction) {
    await setWidgetScanning(false);
  }
  Logger("bgservice").info("Widget seeded with initial data. ScooterName: ${scooterService.scooterName}");

  if (service is AndroidServiceInstance) {
    _androidServiceInstance = service;
    if (backgroundScanEnabled) {
      Logger("bgservice").info("Running first connection cycle");
      _enableScanning();
    } else if (pendingWidgetAction) {
      // _executeAction will promote to foreground itself
    } else {
      Logger("bgservice").info("Background scanning disabled, stopping service");
      _disableScanning();
    }
  }

  // Seed the widget with scooterService data once it's had time to load caches.
  // Skip if we were restarted by a widget action — the widget already has valid data.
  if (!pendingWidgetAction) {
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
          seatClosed: scooterService.seatClosed,
          scooterId: scooterService.myScooter?.remoteId.toString());
    });
  }

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
          scooterId: scooterService.myScooter?.remoteId.toString(),
        );
      });
    } catch (e, stack) {
      Logger("bgservice").severe("Something bad happened on command: $e", e, stack);
    }
  });

  service.on("lock").listen((data) async => _executeAction("lock"));
  service.on("unlock").listen((data) async => _executeAction("unlock"));
  service.on("openseat").listen((data) async => _executeAction("openseat"));

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
      scooterId: scooterService.myScooter?.remoteId.toString(),
    );
    if (backgroundScanEnabled) {
      updateNotification();
    }
    // Fallback: pick up widget actions whose invoke() was lost
    // (e.g. Dart isolate was suspended when the widget tap arrived).
    if (scooterService.connected) {
      _checkPendingWidgetAction();
    }
  });

  // If the service was started by a widget action, execute it now that
  // everything is initialized and all listeners are registered.
  // Wait for scooterService to load cached data (saved scooter IDs, etc.)
  if (pendingWidgetAction && pendingActionName != null) {
    await Future.delayed(const Duration(seconds: 3));
    _executeAction(pendingActionName);
  }

  _rescanTimer = PausableTimer.periodic(const Duration(seconds: 35), () async {
    // Fallback: pick up widget actions that were persisted but never executed.
    _checkPendingWidgetAction();

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
