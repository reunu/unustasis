import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:home_widget/home_widget.dart';
import 'package:unustasis/service/secure_http.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:unustasis/domain/server_notifications.dart';

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

/// Shows the server-pushed dialogs described in `docs/notifications.json`
/// (published as https://reunu.github.io/unustasis/notifications.json).
///
/// An entry is shown when it targets this app (`branch`, `platform`,
/// `build-number`), is inside its `timestamp` + `duration-days` window and is still
/// eligible: not ended by the user, inside `max-shows` and not snoozed.
///
/// The dialog offers up to three answers: the primary action, "Later" (or, without
/// `snooze-days`, a plain dismissal that consumes a show) and "Don't show again".
/// Dismissing the dialog through the barrier or the back button counts as "Later".
Future<void> showServerNotifications(BuildContext context) async {
  final log = Logger('ServerNotifications');
  log.info("Fetching server notifications");
  // get the notifications json from https://reunu.github.io/unustasis/notifications.json
  List<dynamic> notifications;
  try {
    final response = await httpsGet(Uri.parse("https://reunu.github.io/unustasis/notifications.json"));
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
  Map<String, ServerNotificationState> state =
      decodeNotificationState(await prefs.getString(kNotificationStatePrefKey));
  // migrate the older state before clearing it: if the app dies in between, the older
  // values are merged again on the next launch instead of being lost
  final legacyCounts = decodeShownCounts(await prefs.getString(kShownCountsPrefKey));
  final legacyShown = await prefs.getStringList(kLegacyShownPrefKey);
  if (legacyCounts.isNotEmpty || legacyShown != null) {
    state = mergeLegacyState(state, counts: legacyCounts, shownOnceIds: legacyShown);
    await prefs.setString(kNotificationStatePrefKey, encodeNotificationState(state));
    await prefs.remove(kShownCountsPrefKey);
    await prefs.remove(kLegacyShownPrefKey);
  }
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String appName = packageInfo.appName;
  String platform = Platform.operatingSystem;
  int? buildNumber = int.tryParse(packageInfo.buildNumber);

  for (final dynamic entry in notifications) {
    // check for validity
    if (entry is! Map) {
      log.warning("Invalid notification: $entry");
      continue;
    }
    final id = entry['id'];
    final rawTimestamp = entry['timestamp'];
    final durationDays = parseDurationDays(entry['duration-days']);
    final title = entry['title'];
    final body = entry['body'];
    if (id is! String || rawTimestamp is! String || durationDays == null || title is! Map || body is! Map) {
      log.warning("Invalid notification: $entry");
      continue;
    }
    final start = DateTime.tryParse(rawTimestamp);
    if (start == null) {
      log.warning("Invalid date format for notification $id: $rawTimestamp");
      continue;
    }
    // wrap the rest of the handling so one malformed notification can't break the loop or the app
    try {
      // check if this is meant for this branch of the app
      if (entry['branch'] != null && entry['branch'] != appName) {
        log.info("Notification $id is only meant for this branch: ${entry['branch']}. Skipping.");
        continue;
      }
      // check if this is meant for this platform
      if (entry['platform'] != null && entry['platform'] != platform) {
        log.info("Notification $id is only meant for this platform: ${entry['platform']}. Skipping.");
        continue;
      }
      // check if this is meant for this app's build number (build-number, min-build-number, max-build-number)
      final buildScope = matchBuildNumber(
        exact: entry['build-number'],
        min: entry['min-build-number'],
        max: entry['max-build-number'],
        buildNumber: buildNumber,
      );
      // check if this is meant for how the app was installed (installer-store)
      final storeScope = matchInstallerStore(
        value: entry['installer-store'],
        installerStore: packageInfo.installerStore,
      );
      // check if this is meant for how old this installation is (min/max-install-time, min/max-update-time)
      final installScope = matchInstallTimes(
        minInstallTime: entry['min-install-time'],
        maxInstallTime: entry['max-install-time'],
        minUpdateTime: entry['min-update-time'],
        maxUpdateTime: entry['max-update-time'],
        installTime: packageInfo.installTime,
        updateTime: packageInfo.updateTime,
      );
      if (buildScope != ScopeMatch.match || storeScope != ScopeMatch.match || installScope != ScopeMatch.match) {
        // a scope that cannot be evaluated is skipped like a non-matching one, so a typo
        // in the payload can never turn into an unscoped notification
        log.warning("Notification $id does not match this app: build $buildScope ($buildNumber), "
            "installer-store $storeScope (${packageInfo.installerStore}), install dates $installScope "
            "(${packageInfo.installTime}, ${packageInfo.updateTime}). Skipping.");
        continue;
      }
      // check for already shown notifications, allowing repeats up to max-shows (default 1)
      final maxShows = maxShowsOf(entry['max-shows']);
      final notificationState = state[id] ?? ServerNotificationState.initial;
      if (!isEligible(state: notificationState, maxShows: maxShows, now: DateTime.now())) {
        log.info("Notification $id is not eligible: shown ${notificationState.count}/$maxShows times, "
            "done=${notificationState.done}, snoozed until ${notificationState.snoozedUntil}");
        continue;
      }
      // check for timeframe
      if (!isWithinWindow(start: start, durationDays: durationDays, now: DateTime.now())) {
        log.info("Notification $id is not valid for current time");
        continue;
      }
      // make sure we still have a context
      if (!context.mounted) {
        log.warning("Context is not mounted, skipping notification");
        continue;
      }
      final actionUri = tryActionUri(entry['action-url']);
      if (entry['action-url'] != null && actionUri == null) {
        log.warning("Ignoring unusable action-url for notification $id: ${entry['action-url']}");
      }
      // snooze-days turns the dismiss button into a real "Later": the choice is deferred
      // instead of consuming a show, so the entry comes back after the snooze
      final snoozeDays = parseDurationDays(entry['snooze-days']);
      if (entry['snooze-days'] != null && snoozeDays == null) {
        log.warning("Ignoring unusable snooze-days for notification $id: ${entry['snooze-days']}");
      }
      final neverText = entry['never-text'];
      // without snooze-days a dismissal stays what it always was: final
      final dismissalOutcome = snoozeDays == null ? NotificationOutcome.dismissed : NotificationOutcome.later;
      final languageCode = FlutterI18n.currentLocale(context)?.languageCode;
      log.info("Showing notification: $id");
      // show the notification
      final outcome = await showDialog<NotificationOutcome>(
        context: context,
        barrierDismissible: true, // dismissing the dialog counts as "Later"
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(localizedText(title, languageCode, "Notification")),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(localizedText(body, languageCode, "")),
                ],
              ),
            ),
            actions: <Widget>[
              if (actionUri != null)
                TextButton(
                  child: Text(localizedText(entry['action-text'], languageCode, "Open")),
                  onPressed: () async {
                    Navigator.of(context).pop(NotificationOutcome.acted);
                    if (await canLaunchUrl(actionUri)) {
                      await launchUrl(actionUri);
                    } else {
                      log.warning("Could not launch URL: $actionUri");
                    }
                  },
                ),
              TextButton(
                child:
                    Text(localizedText(entry['dismiss-text'], languageCode, snoozeDays == null ? "Dismiss" : "Later")),
                onPressed: () {
                  Navigator.of(context).pop(dismissalOutcome);
                },
              ),
              if (neverText is Map)
                TextButton(
                  child: Text(localizedText(neverText, languageCode, "Don't show again")),
                  onPressed: () {
                    Navigator.of(context).pop(NotificationOutcome.neverAgain);
                  },
                ),
            ],
          );
        },
      );
      // dismissing through the barrier or the back button means the same as "Later"
      final nextState = applyOutcome(
        notificationState,
        outcome ?? dismissalOutcome,
        snoozeDays: snoozeDays,
        now: DateTime.now(),
      );
      log.info("Notification $id outcome: ${outcome ?? dismissalOutcome}, state: ${nextState.toJson()}");
      // persist the state right away, so it survives an app that dies while the dialog is
      // open and a later launch cannot show the same entry again
      state[id] = nextState;
      await prefs.setString(kNotificationStatePrefKey, encodeNotificationState(state));
    } catch (e, stack) {
      log.warning("Skipping malformed notification $id", e, stack);
      continue;
    }
  }
}
