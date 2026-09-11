import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/actions.dart' as core;
import 'package:unustasis/domain/statistics_helper.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('native identity and Dart widget/background consumers retain Unustasis identifiers', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();
    expect(gradle, contains('de.freal.unustasis'));
    expect(gradle, contains('applicationIdSuffix ".debug"'));
    for (final path in ['lib/scooter_service.dart', 'lib/background/bg_service.dart', 'lib/background/widget_handler.dart']) {
      final text = File(path).readAsStringSync();
      expect(text, contains('group.de.freal.unustasis'), reason: path);
      expect(text, isNot(contains('group.com.librescoot.app')), reason: path);
    }
    final background = File('lib/background/bg_service.dart').readAsStringSync();
    expect(background, contains('handleForegroundConnectionUpdate(scooterService, data)'));
    for (final retained in ['scooterService.scooterName = data!["scooterName"]',
      'scooterService.scooterColor = data!["scooterColor"]',
      'DateTime.fromMillisecondsSinceEpoch(data!["lastPingInt"])']) {
      expect(background, contains(retained));
    }
  });

  test('event enums retain identity, names, ordering, timestamps and location JSON', () {
    expect(EventType.values, same(core.EventType.values));
    expect(EventSource.values, same(core.EventSource.values));
    expect(EventType.values.map((e) => e.toString()), [
      'EventType.lock', 'EventType.unlock', 'EventType.openSeat',
      'EventType.hibernate', 'EventType.wakeUp', 'EventType.unknown',
    ]);
    expect(EventSource.values.map((e) => e.toString()), [
      'EventSource.app', 'EventSource.background', 'EventSource.auto', 'EventSource.unknown',
    ]);
    final time = DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7);
    final entry = LogEntry(timestamp: time, eventType: EventType.lock,
        source: EventSource.background, scooterId: 'A', soc1: 0, soc2: null,
        location: const LatLng(51.2, 13.4));
    final decoded = jsonDecode(entry.toJsonString()) as Map<String, dynamic>;
    expect(decoded, {
      'timestamp': '2026-01-02T03:04:05.006007Z', 'eventType': 'EventType.lock',
      'source': 'EventSource.background', 'scooterId': 'A', 'soc1': 0, 'soc2': null,
      'location': const LatLng(51.2, 13.4).toJson(),
    });
    expect(LogEntry.fromJsonString(entry.toJsonString()).toJsonString(), entry.toJsonString());
  });

  test('single shared owners replace root connection, probe, action and queue algorithms', () {
    final source = File('lib/scooter_service.dart').readAsStringSync();
    for (final owner in ['ScooterSession', 'ScooterTelemetry', 'ScooterActions', 'NavigationRuntime', 'UpdateController']) {
      expect(RegExp('$owner\\(').allMatches(source), hasLength(1), reason: owner);
    }
    for (final legacy in ['_autoRestartSubscription', '_connectionStateSubscription',
      '_waitForScooterState(', '_probeLsCapabilities(', 'PausableTimer', 'StateWaiter<']) {
      expect(source, isNot(contains(legacy)), reason: legacy);
    }
    final commands = File('lib/service/ble_commands.dart').readAsStringSync();
    expect(commands, isNot(contains('withExtendedChannel(')));
    expect(commands, contains('package:scooter_flutter/navigation_commands.dart'));
    expect(commands, isNot(contains('_extendedChannelQueue')));
    expect(source, isNot(contains('_activeNavigation')));
  });

  test('action UI uses session-targeted APIs and visible warnings, not failed acknowledgements', () {
    for (final name in ['ls_keycard_screen', 'ls_scheduled_hibernation_screen', 'ls_settings_screen']) {
      final source = File('lib/ui/screens/$name.dart').readAsStringSync();
      expect(source, isNot(contains('characteristicRepository')), reason: name);
      expect(source, contains('.actions.'));
    }
    final home = File('lib/ui/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('service.actionWarnings.listen'));
    expect(home, contains('showHandlebarWarning(didNotUnlock: warning.didNotUnlock)'));
    expect(home, contains('_warningSubscription?.cancel()'));
    expect(home, isNot(contains('on HandlebarLockException')));
    final saved = File('lib/ui/screens/stats/scooter_screen.dart').readAsStringSync();
    expect(saved, contains('if (!context.mounted || service.savedScooters.containsKey(id)) return;'));
  });
  test('pending consumers do not clear at startup and notification producers persist before invoke', () {
    final background = File('lib/background/bg_service.dart').readAsStringSync();
    final startup = background.substring(background.indexOf('void onStart('));
    expect(startup, isNot(contains('setBool("pendingWidgetAction", false)')));
    expect(startup, isNot(contains('remove("pendingWidgetActionName")')));
    expect(startup, contains('executeWidgetAction(pendingActionName)'));
    final notification = File('lib/background/notification_handler.dart').readAsStringSync();
    for (final identity in ["'unu_foreground'", "'Unu Background Connection'",
      "'unu_service'", "'Unu Background Service'", 'const notificationId = 1612']) {
      expect(notification, contains(identity));
    }
    final persist = notification.indexOf('prefs.setString("pendingWidgetActionName", action!)');
    expect(persist, greaterThan(0));
    expect(notification.indexOf('FlutterBackgroundService().invoke(action)'), greaterThan(persist));
    // These are the only app producers of the three explicit action channels.
    final producers = <String>[];
    final invoke = RegExp(r'''invoke\(['"](?:lock|unlock|openseat)['"]\)|invoke\(action\)''');
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart') && invoke.hasMatch(file.readAsStringSync())) producers.add(file.path);
    }
    expect(producers, unorderedEquals([
      'lib/background/widget_handler.dart', 'lib/background/notification_handler.dart',
    ]));
  });

}
