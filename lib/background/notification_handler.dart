import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../background/bg_service.dart';
import '../background/background_i18n.dart';
import '../background/translate_static.dart';
import '../domain/scooter_state.dart';

// Notification identifiers
const notificationChannelId = 'unu_foreground';
const notificationChannelName = 'Unu Background Connection';
const serviceChannelId = 'unu_service';
const serviceChannelName = 'Unu Background Service';
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

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  // Silent channel for the mandatory foreground service notification
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      serviceChannelId,
      serviceChannelName,
      description: 'Required for background operation. You can hide this channel.',
      importance: Importance.min,
    ),
  );

  // Functional channel for scooter state & action buttons
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      notificationChannelId,
      notificationChannelName,
      description: 'Shows scooter status and quick actions.',
      importance: Importance.low,
    ),
  );
  return;
}

/// Re-creates notification channels with localized names.
/// Must be called after BackgroundI18n.instance.init().
/// Android allows re-creating channels to update display names.
void localizeNotificationChannels() {
  final i18n = BackgroundI18n.instance;
  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  androidPlugin?.createNotificationChannel(
    AndroidNotificationChannel(
      serviceChannelId,
      i18n.translate('notification_channel_service'),
      description: i18n.translate('notification_channel_service_description'),
      importance: Importance.min,
    ),
  );

  androidPlugin?.createNotificationChannel(
    AndroidNotificationChannel(
      notificationChannelId,
      i18n.translate('notification_channel_connection'),
      description: i18n.translate('notification_channel_connection_description'),
      importance: Importance.low,
    ),
  );
}

void updateNotification({String? debugText}) async {
  if (backgroundScanEnabled) {
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
