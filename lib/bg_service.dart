import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'scooter_service.dart'; // Reference your existing ScooterService class

ScooterService scooterService = ScooterService();

Future<void> initializeBackgroundService() async {
  // Request background execution permissions
  await FlutterBackground.initialize();

  final service = FlutterBackgroundService();

  // Start the service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'scooter_service_channel',
      initialNotificationTitle: 'Scooter Service',
      initialNotificationContent: 'Managing scooter connection',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Initialize ScooterService here
  scooterService.connect();

  // Listen to events and commands from the home screen widget or other parts
  service.on('unlock_scooter').listen((event) {
    scooterService.unlock();
  });

  service.on('lock_scooter').listen((event) {
    scooterService.lock();
  });

  // Periodically update the scooter's battery status
  Timer.periodic(Duration(minutes: 5), (timer) async {
    if (service.isStopped) timer.cancel();
    final batteryLevel = await scooterService.getBatteryLevel();
    service.invoke('update', {'battery': batteryLevel.toString()});
  });
}

// Required for iOS background execution (empty function)
@pragma('vm:entry-point')
void onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
}
