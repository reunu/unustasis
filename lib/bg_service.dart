import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'scooter_service.dart'; // Reference your existing ScooterService class

FlutterBluePlusMockable flutterBluePlus = FlutterBluePlusMockable();
ScooterService scooterService = ScooterService(flutterBluePlus);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initializeBackgroundService() async {
  // Initialize notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'scooter_service_channel', // id
    'Scooter Service Channel', // title
    description: 'This channel is used by the scooter background service',
    importance: Importance.low, // Set the importance level
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Request background execution permissions
  await FlutterBackground.initialize();

  final service = FlutterBackgroundService();

  // Start the service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: channel.id,
      initialNotificationTitle: 'Scooter Service',
      initialNotificationContent: 'Managing scooter connection',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackgroundAsync,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Initialize ScooterService here
  scooterService.start();

  // Listen to events and commands from the home screen widget or other parts
  service.on('unlock_scooter').listen((event) {
    scooterService.unlock();
  });

  service.on('lock_scooter').listen((event) {
    scooterService.lock();
  });

  // Periodically update the scooter's battery status
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        timer.cancel();
      }
    }
    final batteryLevel = scooterService.primarySOC;
    service.invoke('update', {'battery': batteryLevel.toString()});
  });
}

// Required for iOS background execution (async function)
@pragma('vm:entry-point')
Future<bool> onIosBackgroundAsync(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the service alive for periodic updates
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    final batteryLevel = scooterService.primarySOC;
    service.invoke('update', {'battery': batteryLevel.toString()});
  });
  return true;
}
