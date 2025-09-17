import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the Android home widget onboarding dialog if not shown before
Future<void> showWidgetOnboarding(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false, // user must tap button!
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(FlutterI18n.translate(context, "widget_onboarding_title")),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text(FlutterI18n.translate(context, "widget_onboarding_body")),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(FlutterI18n.translate(context, "widget_onboarding_place")),
            onPressed: () async {
              if ((await HomeWidget.isRequestPinWidgetSupported()) == true) {
                HomeWidget.requestPinWidget(
                  name: 'HomeWidgetReceiver',
                  androidName: 'HomeWidgetReceiver',
                  qualifiedAndroidName:
                      'com.unumotors.ossapp.HomeWidgetReceiver',
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text(FlutterI18n.translate(context, "widget_onboarding_dismiss")),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

/// Shows server notifications from the notifications.json file if they haven't been shown before
Future<void> showServerNotifications(BuildContext context) async {
  final log = Logger('ServerNotifications');
  log.info("Fetching server notifications");
  // get the notifications json from https://reunu.github.io/unustasis/notifications.json
  List<dynamic> notifications;
  try {
    final response = await get(Uri.parse("https://reunu.github.io/unustasis/notifications.json"));
    if (response.statusCode != 200) {
      log.warning("Failed to fetch notifications: ${response.statusCode}");
      return;
    }
    log.info("Successfully fetched notifications");

    notifications = json.decode(response.body) as List<dynamic>;
    if (notifications.isEmpty) {
      log.warning("No notifications found");
      return;
    }
  } catch (e, stack) {
    log.severe("Failed to fetch or parse notifications", e, stack);
    return;
  }

  SharedPreferencesAsync prefs = SharedPreferencesAsync();
  List<String> shownServerNotifications = await prefs.getStringList("shownServerNotifications") ?? [];
  String appName = (await PackageInfo.fromPlatform()).appName;
  String platform = Platform.operatingSystem;

  for (var notification in notifications) {
    // check for validity
    if (notification['id'] == null ||
        notification['timestamp'] == null ||
        notification['duration-days'] == null ||
        notification['title'] == null ||
        notification['body'] == null) {
      log.warning("Invalid notification: $notification");
      continue;
    }
    // check if this is meant for this branch of the app
    if (notification['branch'] != null && notification['branch'] != appName) {
      log.info(
          "Notification ${notification['id']} is only meant for this branch: ${notification['branch']}. Skipping.");
      continue;
    }
    // check if this is meant for this platform
    if (notification['platform'] != null && notification['platform'] != platform) {
      log.info(
          "Notification ${notification['id']} is only meant for this platform: ${notification['platform']}. Skipping.");
      continue;
    }
    // check for already shown notifications
    if (shownServerNotifications.contains(notification['id'])) {
      log.info("Notification ${notification['id']} already shown");
      continue;
    }
    // check for timeframe
    DateTime timestamp;
    int durationDays;
    try {
      timestamp = DateTime.parse(notification['timestamp']);
      durationDays = notification['duration-days'] as int;
      if (durationDays < 0) {
        log.warning("Invalid duration for notification ${notification['id']}: $durationDays days");
        continue;
      }
      if (timestamp.isAfter(DateTime.now()) || timestamp.add(Duration(days: durationDays)).isBefore(DateTime.now())) {
        log.info("Notification ${notification['id']} is not valid for current time");
        continue;
      }
    } catch (e) {
      log.warning("Invalid date format for notification ${notification['id']}: ${notification['timestamp']}", e);
      continue;
    }
    // make sure we still have a context
    if (!context.mounted) {
      log.warning("Context is not mounted, skipping notification");
      continue;
    }
    log.info("Showing notification: ${notification['id']}");
    // show the notification
    await showDialog<void>(
      context: context,
      barrierDismissible: true, // user can dismiss the dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(notification['title'][FlutterI18n.currentLocale(context)?.languageCode] ??
              notification['title']['en'] ??
              "Notification"),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(notification['body'][FlutterI18n.currentLocale(context)?.languageCode] ??
                    notification['body']['en'] ??
                    ""),
              ],
            ),
          ),
          actions: <Widget>[
            if (notification["action-url"] != null)
              TextButton(
                child: Text(notification["action-text"][FlutterI18n.currentLocale(context)?.languageCode] ??
                    notification["action-text"]["en"] ??
                    "Open"),
                onPressed: () async {
                  if (await canLaunchUrl(Uri.parse(notification["action-url"]))) {
                    await launchUrl(Uri.parse(notification["action-url"]));
                  } else {
                    log.warning("Could not launch URL: ${notification["action-url"]}");
                  }
                },
              ),
            TextButton(
              child: Text(notification["dismiss-text"][FlutterI18n.currentLocale(context)?.languageCode] ??
                  notification["dismiss-text"]["en"] ??
                  "Dismiss"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    // add the notification to the list of shown notifications
    shownServerNotifications.add(notification['id']);
    // save the list of shown notifications
  }
  await prefs.setStringList("shownServerNotifications", shownServerNotifications);
}
