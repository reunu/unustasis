import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';

// this will be used as notification channel id
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';

// this will be used for notification id, So you can update your custom notification with this id.
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
  // update all data we have
  await HomeWidget.saveWidgetData<bool>('connected', scooterService.connected);
  await HomeWidget.saveWidgetData<bool>('scanning', scooterService.scanning);
  await HomeWidget.saveWidgetData<bool>(
      'poweredOn', scooterService.state?.isOn ?? false);
  await HomeWidget.saveWidgetData<int>('tick', DateTime.now().second);
  await HomeWidget.saveWidgetData<int>('soc1', scooterService.primarySOC);
  await HomeWidget.saveWidgetData<int>('soc2', scooterService.secondarySOC);

// once all is set, rebuild the widget
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

Future<void> setupNotificationService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    notificationChannelName, // title
    description:
        'This channel is used for periodically checking your scooter.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

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
      initialNotificationTitle: 'Unu Background Connection',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: notificationId,
    ),
  );
}

void updateNotification() async {
  FlutterLocalNotificationsPlugin().show(
    notificationId,
    notificationChannelName,
    'Time: ${DateTime.now()}, Scanning: ${scooterService.scanning} Connected: ${scooterService.connected}',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        notificationChannelName,
        icon: 'ic_bg_service_small',
        ongoing: true,
      ),
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
  // perform the requested action
  switch (data.toString().split("://")[1]) {
    case "lock":
      scooterService.lock();
    // await HomeWidget.saveWidgetData<bool>('poweredOn', false);
    case "unlock":
      scooterService.unlock();
    // await HomeWidget.saveWidgetData<bool>('poweredOn', true);
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Logger("BackgroundService").info("Background service started!");

  HomeWidget.registerInteractivityCallback(backgroundCallback);

  try {
    scooterService.start(restart: true);
  } catch (e) {
    Logger("BackgroundService")
        .info("Error while starting the scooter service");
  }

  // set up state values
  bool connected = scooterService.connected;
  DateTime? lastPing = scooterService.lastPing;
  ScooterState? state = scooterService.state;
  int? scooterColor = scooterService.scooterColor;
  int? primarySOC = scooterService.primarySOC;
  int? secondarySOC = scooterService.secondarySOC;
  bool scanning = scooterService.scanning; // debug

  // listen to changes
  scooterService.addListener(() {
    print("ScooterService updated");
    if (connected != scooterService.connected ||
        lastPing != scooterService.lastPing ||
        state != scooterService.state ||
        scooterColor != scooterService.scooterColor ||
        primarySOC != scooterService.primarySOC ||
        secondarySOC != scooterService.secondarySOC ||
        scanning != scooterService.scanning) {
      // update state values
      connected = scooterService.connected;
      lastPing = scooterService.lastPing;
      state = scooterService.state;
      scooterColor = scooterService.scooterColor;
      primarySOC = scooterService.primarySOC;
      secondarySOC = scooterService.secondarySOC;
      scanning = scooterService.scanning; // debug
      // update home screen widget
      updateWidget();
    }
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update Notification
        updateNotification();
        // Update widget
        updateWidget();
      }
    }
  });
}
