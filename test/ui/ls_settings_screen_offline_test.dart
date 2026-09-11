import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/screens/ls_settings_screen.dart';

class _Actions extends Fake implements ScooterActions {
  int reads = 0;
  Completer<int?>? gate;
  bool failReads = false;
  bool nullReads = false;
  @override
  Future<int?> countKeycards() async {
    reads++;
    if (failReads) throw TimeoutException('extended channel');
    if (nullReads) return null;
    return gate == null ? 2 : await gate!.future;
  }
}

class _Service extends ChangeNotifier implements ScooterService {
  @override
  bool connected = false;
  @override
  String? currentScooterId = 'A';
  @override
  final identity = ScooterIdentity()..isLibrescoot = true;
  @override
  final vehicle = VehicleStatus();
  @override
  final _Actions actions = _Actions();
  @override
  bool get otaAvailable => true;
  @override
  bool get alarmAvailable => false;
  final reads = <String>[];
  Completer<String?>? apnGate;
  Completer<bool?>? batteryGate;
  Completer<bool?>? alarmGate;
  bool failReads = false;
  bool nullReads = false;
  final apnWrites = <String>[];
  @override
  Future<void> setCellularApn(String value) async => apnWrites.add(value);
  @override
  Future<String?> getCellularApn() async {
    reads.add('apn');
    if (failReads) throw TimeoutException('extended channel');
    if (nullReads) return null;
    return apnGate == null ? 'current-apn' : await apnGate!.future;
  }

  @override
  Future<bool?> getBatteryKeepActive() async {
    reads.add('battery');
    if (failReads) throw TimeoutException('extended channel');
    if (nullReads) return null;
    return batteryGate == null ? true : await batteryGate!.future;
  }

  @override
  Future<bool?> getAlarmEnabled() async {
    reads.add('alarm');
    if (failReads) throw TimeoutException('extended channel');
    if (nullReads) return null;
    return alarmGate == null ? true : await alarmGate!.future;
  }

  @override
  Future<bool?> getAlarmHonk() async {
    reads.add('honk');
    if (failReads) throw TimeoutException('extended channel');
    if (nullReads) return null;
    return false;
  }

  void change(bool value, {String? id}) {
    connected = value;
    if (id != null) currentScooterId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected write or service call: ${invocation.memberName}');
}

Widget _screen(_Service service) => ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          )),
        ],
        home: const LsSettingsScreen(),
      ),
    );

Future<void> _show(WidgetTester tester, Finder finder) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
  scrollable.position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 150, scrollable: find.byType(Scrollable).first);
}

void main() {
  for (final failure in ['timeout', 'null']) {
    testWidgets('current $failure reads settle unavailable without loading or writable unknown switches', (tester) async {
      final service = _Service()..connected = true;
      service.identity
        ..supportsBatteryKeepActive = true
        ..supportsAlarmControl = true
        ..supportsApnConfig = true;
      service.failReads = service.actions.failReads = failure == 'timeout';
      service.nullReads = service.actions.nullReads = failure == 'null';
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      for (final key in ['ls_settings_battery_keep_active_title', 'ls_settings_alarm_title',
        'ls_settings_alarm_honk_title', 'ls_keycard_title']) {
        final title = find.text(FlutterI18n.translate(tester.element(find.byType(LsSettingsScreen)), key));
        await _show(tester, title);
        final tile = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
        expect((tile.subtitle as Text).data, 'Unavailable on this connection', reason: key);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (key == 'ls_keycard_title') {
          expect(tile.onTap, isNull);
          expect(tile.trailing, isNull);
        } else {
          expect((tile.trailing as Switch).onChanged, isNull);
        }
      }
      expect(service.reads, isNot(contains('honk')), reason: 'No secondary read after missing primary alarm setting');
      expect(tester.takeException(), isNull);
    });
  }

  for (final replacement in ['disconnect', 'B', 'same-id', 'provider', 'dispose']) {
    testWidgets('stale extended read failures cannot mark $replacement target unavailable', (tester) async {
      final old = _Service()..connected = true;
      old.identity..supportsBatteryKeepActive = true..supportsAlarmControl = true;
      final cards = Completer<int?>();
      final apn = Completer<String?>();
      final battery = Completer<bool?>();
      final alarm = Completer<bool?>();
      old.actions.gate = cards;
      old.apnGate = apn;
      old.batteryGate = battery;
      old.alarmGate = alarm;
      await tester.pumpWidget(_screen(old));
      await tester.pump();
      _Service current = old;
      if (replacement == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else if (replacement == 'provider') {
        current = _Service()..connected = true;
        current.identity..supportsBatteryKeepActive = true..supportsAlarmControl = true;
        await tester.pumpWidget(_screen(current));
      } else {
        old.change(false);
        old.actions.gate = null;
        old.apnGate = null;
        old.batteryGate = null;
        old.alarmGate = null;
        if (replacement != 'disconnect') old.change(true, id: replacement == 'B' ? 'B' : 'A');
      }
      await tester.pumpAndSettle();
      for (final gate in [cards, apn, battery, alarm]) {
        gate.completeError(TimeoutException('obsolete extended read'));
      }
      await tester.pumpAndSettle();
      if (replacement != 'dispose' && replacement != 'disconnect') {
        for (final key in ['ls_settings_battery_keep_active_title', 'ls_settings_alarm_title',
          'ls_settings_alarm_honk_title', 'ls_keycard_title']) {
          final title = find.text(FlutterI18n.translate(tester.element(find.byType(LsSettingsScreen)), key));
          await _show(tester, title);
          final tile = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
          expect((tile.subtitle as Text).data, isNot('Unavailable on this connection'));
          if (key == 'ls_keycard_title') {
            expect(tile.onTap, isNotNull);
          } else {
            expect((tile.trailing as Switch).onChanged, isNotNull);
          }
        }
        expect(current.reads.where((r) => r == 'honk'), hasLength(1));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reconnect resets unavailable state to loading until fresh reads finish', (tester) async {
    final service = _Service()..connected = true..failReads = true;
    service.actions.failReads = true;
    service.identity..supportsBatteryKeepActive = true..supportsAlarmControl = true;
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    service.change(false);
    service.failReads = service.actions.failReads = false;
    final cards = service.actions.gate = Completer<int?>();
    final battery = service.batteryGate = Completer<bool?>();
    final alarm = service.alarmGate = Completer<bool?>();
    service.change(true, id: 'B');
    await tester.pump();
    for (final key in ['ls_settings_battery_keep_active_title', 'ls_settings_alarm_title', 'ls_keycard_title']) {
      final title = find.text(FlutterI18n.translate(tester.element(find.byType(LsSettingsScreen)), key));
      await _show(tester, title);
      final tile = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
      expect((tile.subtitle as Text).data, isNot('Unavailable on this connection'));
      if (key == 'ls_keycard_title') {
        expect(tile.onTap, isNull);
      } else {
        expect(tile.trailing, isA<SizedBox>());
      }
    }
    cards.complete(3);
    battery.complete(true);
    alarm.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial offline controls stay visible disabled without reads or loading', (tester) async {
    final service = _Service();
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    for (final key in [
      'ls_settings_clock_title',
      'ls_settings_auto_lock_title',
      'ls_settings_auto_hibernate_title',
      'ls_scheduled_hibernation_title',
      'ls_settings_apn_title',
      'ls_settings_update_mode_title',
      'ls_settings_battery_keep_active_title',
      'ls_settings_alarm_title',
      'ls_keycard_title',
      'ls_settings_ota_title'
    ]) {
      final title = find.text(FlutterI18n.translate(tester.element(find.byType(LsSettingsScreen)), key));
      await _show(tester, title);
      final tile = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
      expect(tile.enabled, isFalse, reason: key);
      expect(tile.onTap, isNull, reason: key);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Switch), findsNothing);
    }
    expect(service.actions.reads, 0);
    expect(service.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final target in ['offline', 'B']) {
    testWidgets('APN dialog opened on A cannot write after $target replacement', (tester) async {
      final service = _Service()..connected = true;
      service.identity.supportsApnConfig = true;
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      await _show(tester, find.text('current-apn'));
      await tester.tap(find.text('current-apn'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new-apn');
      service.change(false);
      if (target == 'B') service.change(true, id: 'B');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(service.apnWrites, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final replacement in ['disconnect', 'B', 'same-id', 'dispose']) {
    testWidgets('obsolete Settings reads are discarded on $replacement and reconnect reloads', (tester) async {
      final service = _Service()..connected = true;
      service.identity.supportsApnConfig = true;
      final old = Completer<String?>();
      service.apnGate = old;
      await tester.pumpWidget(_screen(service));
      await tester.pumpAndSettle();
      expect(service.actions.reads, 1);
      if (replacement == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else {
        service.change(false);
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        service.apnGate = null;
        service.change(true, id: replacement == 'B' ? 'B' : 'A');
        await tester.pumpAndSettle();
        expect(service.actions.reads, 2);
      }
      old.complete('obsolete-apn');
      await tester.pumpAndSettle();
      if (replacement != 'dispose') {
        await _show(tester, find.text('current-apn'));
        expect(find.text('obsolete-apn'), findsNothing);
        expect(service.reads.where((r) => r == 'apn'), hasLength(2));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
