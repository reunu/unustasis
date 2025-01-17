import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';

final log = Logger("BackgroundService");

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

void setWidgetScanning(bool scanning) async {
  await HomeWidget.saveWidgetData<bool>("scanning", scanning);
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

void updateWidget() async {
  // update all data we have
  await HomeWidget.saveWidgetData<bool>("connected", scooterService.connected);
  await HomeWidget.saveWidgetData<bool>("scanning", scooterService.scanning);
  await HomeWidget.saveWidgetData<int>("state", scooterService.state!.index);
  await HomeWidget.saveWidgetData<String>("lastPing",
      scooterService.lastPing?.calculateTimeDifferenceInShort() ?? "");
  await HomeWidget.saveWidgetData<int>("soc1", scooterService.primarySOC);
  await HomeWidget.saveWidgetData<int?>("soc2", scooterService.secondarySOC);
  await HomeWidget.saveWidgetData<String>(
      "scooterName", scooterService.scooterName);

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
          importance:
              Importance.low, // importance must be at low or higher level
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
      initialNotificationTitle: 'Unu Background Connection',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: notificationId,
    ),
  );
}

void updateNotification({String? debugText}) async {
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
  await HomeWidget.setAppGroupId('de.freal.unustasis');
  print("Received data: $data");
  switch (data?.host) {
    case "stop":
      stopBackgroundService();
    case "openlocation":
      print("Opening location");
      MapsLauncher.launchCoordinates(
        scooterService.lastLocation!.latitude,
        scooterService.lastLocation!.longitude,
      );
    case "ping":
      print("pong");
      scooterService.testPing();
  }
  await HomeWidget.updateWidget(
    qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print("Background service started!");

  HomeWidget.registerInteractivityCallback(backgroundCallback);

  try {
    if ((await scooterService.getSavedScooterIds()).isNotEmpty) {
      scooterService.start();
    } else {
      print("No saved scooters found. Won't start the scooter service.");
      // user has not set up any scooters to connect to
    }
  } catch (e) {
    print("Error while starting the scooter service");
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
    if (true) {
      // TODO
      print("Relevant values have changed");
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
      updateNotification();
    } else {
      print("No relevant values have changed");
    }
  });

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        if (!scooterService.scanning && !scooterService.connected) {
          // must have been killed along the way
          // make sure we're not just between auto-restarts
          await Future.delayed(const Duration(seconds: 5));
          if (!scooterService.scanning && !scooterService.connected) {
            scooterService.start();
          }
        }
      }
    }
  });
}

extension DateTimeExtension on DateTime {
  String calculateTimeDifferenceInShort() {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '1W';
    } else if (difference.inDays >= 2) {
      return '${difference.inDays}D';
    } else if (difference.inDays >= 1) {
      return '1D';
    } else if (difference.inHours >= 2) {
      return '${difference.inHours}H';
    } else if (difference.inHours >= 1) {
      return '1H';
    } else if (difference.inMinutes >= 2) {
      return '${difference.inMinutes}M';
    } else if (difference.inMinutes >= 1) {
      return '1M';
    } else {
      return "";
    }
  }
}
