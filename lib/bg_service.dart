import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

// this will be used as notification channel id
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Connection Foreground Service';

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
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: notificationId,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  service.on("lock").listen((event) {
    scooterService.lock();
  });

  service.on("unlock").listen((event) {
    scooterService.unlock();
  });

  Logger("BackgroundService").info("Background service started!");

  try {
    scooterService.start(restart: true);
  } catch (e) {
    Logger("BackgroundService")
        .info("Error while starting the scooter service");
  }

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update Notification
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

        // Update widget
        await HomeWidget.saveWidgetData<String>(
            'title', scooterService.scanning ? "Scanning" : "Not scanning");
        await HomeWidget.saveWidgetData<String>(
            'message', DateTime.now().toString());

        Logger("BackgroundService")
            .info("Now I would update the widget using HomeWidgetReceiver");

        await HomeWidget.updateWidget(
          qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
        );
        Logger("BackgroundService").info("Widget updated");
      }
    }
  });

  Timer.periodic(const Duration(minutes: 1), (timer) {
    // look for our scooter, connect to it, poll state and battery levels
  });
}
