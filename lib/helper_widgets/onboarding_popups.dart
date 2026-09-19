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

// Shows the Android home widget onboarding dialog if not shown before
// Currently not used, but can be used for future onboarding related to the widget or other features
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
                  qualifiedAndroidName: 'de.freal.unustasis.HomeWidgetReceiver',
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
  Map<String, int> shownCounts = {};
  try {
    final rawCounts = await prefs.getString("shownServerNotificationCounts");
    if (rawCounts != null) {
      (json.decode(rawCounts) as Map).forEach((id, count) => shownCounts[id as String] = count as int);
    }
  } catch (e) {
    log.warning("Could not read shown notification counts, resetting", e);
  }
  // migrate the old shown-once list, so previously-seen notifications aren't shown again
  final legacyShown = await prefs.getStringList("shownServerNotifications");
  if (legacyShown != null) {
    for (final id in legacyShown) {
      shownCounts.putIfAbsent(id, () => 1);
    }
    await prefs.remove("shownServerNotifications");
  }
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String appName = packageInfo.appName;
  String platform = Platform.operatingSystem;
  int? buildNumber = int.tryParse(packageInfo.buildNumber);

  for (var notification in notifications) {
    // check for validity
    if (notification is! Map ||
        notification['id'] is! String ||
        notification['timestamp'] is! String ||
        notification['duration-days'] is! int ||
        notification['title'] is! Map ||
        notification['body'] is! Map) {
      log.warning("Invalid notification: $notification");
      continue;
    }
    // wrap the rest of the handling so one malformed notification can't break the loop or the app
    try {
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
      // check if this is meant for this app's build number (build-number, min-build-number, max-build-number)
      if (!_matchesBuildNumber(notification, buildNumber)) {
        log.info("Notification ${notification['id']} does not match this build number ($buildNumber). Skipping.");
        continue;
      }
      // check for already shown notifications, allowing repeats up to max-shows (default 1)
      int maxShows =
          notification['max-shows'] is int && notification['max-shows'] > 0 ? notification['max-shows'] as int : 1;
      int shownCount = shownCounts[notification['id']] ?? 0;
      if (shownCount >= maxShows) {
        log.info("Notification ${notification['id']} already shown $shownCount/$maxShows times");
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
                  child: Text(notification["action-text"]?[FlutterI18n.currentLocale(context)?.languageCode] ??
                      notification["action-text"]?["en"] ??
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
                child: Text(notification["dismiss-text"]?[FlutterI18n.currentLocale(context)?.languageCode] ??
                    notification["dismiss-text"]?["en"] ??
                    "Dismiss"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      // record that the notification was shown, so it counts towards max-shows
      shownCounts[notification['id']] = shownCount + 1;
    } catch (e, stack) {
      log.warning("Skipping malformed notification ${notification['id']}", e, stack);
      continue;
    }
  }
  await prefs.setString("shownServerNotificationCounts", json.encode(shownCounts));
}

// Checks the optional build-number / min-build-number / max-build-number fields against the
// current app's build number. No fields set means no constraint. If a constraint is set but the
// current build number couldn't be determined, the notification is not shown.
bool _matchesBuildNumber(Map notification, int? buildNumber) {
  final exact = notification['build-number'];
  final min = notification['min-build-number'];
  final max = notification['max-build-number'];
  if (exact == null && min == null && max == null) return true;
  if (buildNumber == null) return false;
  if (exact is List && !exact.contains(buildNumber)) return false;
  if (exact != null && exact is! List && exact != buildNumber) return false;
  if (min is num && buildNumber < min) return false;
  if (max is num && buildNumber > max) return false;
  return true;
}
