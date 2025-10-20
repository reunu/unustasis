import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../background/bg_service.dart';
import '../background/translate_static.dart';
import '../domain/scooter_state.dart';

// Notification identifiers
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';
const notificationId = 1612;

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> setupNotifications() async {
  await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("ic_bg_service_small"),
      ),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: notificationTapBackground);

  flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationChannelId,
          notificationChannelName,
          description: 'This channel is used for periodically checking your scooter.',
          importance: Importance.low,
        ),
      );
  return;
}

void updateNotification({String? debugText}) async {
  if (backgroundScanEnabled && (await scooterService.getSavedScooterIds(onlyAutoConnect: true)).isNotEmpty) {
    flutterLocalNotificationsPlugin.show(
      notificationId,
      "Unu Scooter",
      scooterService.state?.getNameStatic(),
      NotificationDetails(
        android: AndroidNotificationDetails(notificationChannelId, notificationChannelName,
            icon: 'ic_bg_service_small',
            ongoing: true,
            importance: Importance.max,
            priority: Priority.high,
            autoCancel: false,
            actions: getAndroidNotificationActions(scooterService.state)),
      ),
    );
  } else {
    dismissNotification();
  }
}

void dismissNotification() {
  flutterLocalNotificationsPlugin.cancel(notificationId);
}

List<AndroidNotificationAction> getAndroidNotificationActions(ScooterState? state) {
  switch (state) {
    case ScooterState.standby:
      return [
        AndroidNotificationAction("unlock", getLocalizedNotificationAction("unlock")),
        AndroidNotificationAction("openseat", getLocalizedNotificationAction("openseat"))
      ];
    case ScooterState.parked:
      return [
        AndroidNotificationAction(
          "lock",
          getLocalizedNotificationAction("lock"),
        ),
        AndroidNotificationAction(
          "openseat",
          getLocalizedNotificationAction("openseat"),
        ),
        AndroidNotificationAction(
          "unlock",
          getLocalizedNotificationAction("unlock"),
        )
      ];
    default:
      return [];
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  switch (notificationResponse.actionId) {
    case "unlock":
      FlutterBackgroundService().invoke("unlock");
      break;
    case "lock":
      FlutterBackgroundService().invoke("lock");
      break;
    case "openseat":
      FlutterBackgroundService().invoke("openseat");
      break;
  }
}
