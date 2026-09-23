import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/state/vehicle_status.dart';
import 'package:unustasis/stats/settings_screen.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends ChangeNotifier implements ScooterService {
  _Service({this.state, Map<String, SavedScooter>? savedScooters}) : _savedScooters = savedScooters ?? {};
  final Map<String, SavedScooter> _savedScooters;
  @override
  final ScooterState? state;
  @override
  final identity = ScooterIdentity()..isLibrescoot = true;
  @override
  final vehicle = VehicleStatus();
  @override
  bool get connected => false;
  @override
  bool get autoUnlock => false;
  @override
  int get autoUnlockThreshold => -65;
  @override
  bool get openSeatOnUnlock => false;
  @override
  bool get hazardLocking => false;
  // The settings screen reads the saved-scooter store for app-local per-scooter
  // preferences; an empty store is expected while disconnected in this test.
  @override
  Map<String, SavedScooter> get savedScooters => _savedScooters;
  // Any attempted transport access/read/write is unexpected while disconnected.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw TestFailure('Unexpected scooter access: ${invocation.memberName}');
}

void main() {
  testWidgets('offline Librescoot controls stay visible and disabled without loading or transport access', (tester) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'), (call) async => <String>[]);
    final service = _Service();
    addTearDown(service.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(initialThemeMode: ThemeMode.light, child: MaterialApp(
        localizationsDelegates: [FlutterI18nDelegate(translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))],
        home: const SettingsScreen(),
      )),
    ));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SettingsScreen));
    for (final key in ['ls_keycard_title', 'ls_settings_auto_lock_title',
      'ls_settings_auto_hibernate_title', 'ls_scheduled_hibernation_title',
      'ls_settings_battery_keep_active_title', 'ls_settings_alarm_title',
      'ls_settings_alarm_honk_title', 'ls_settings_alarm_watch_title',
      'ls_settings_apn_title', 'ls_settings_ota_title',
      'ls_settings_update_mode_title']) {
      final title = find.text(FlutterI18n.translate(context, key));
      await tester.scrollUntilVisible(title, 180, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final row = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
      expect(row.enabled, isFalse, reason: key);
      expect(row.onTap, isNull, reason: key);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hibernating scooter shows its controls, visible but inert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    final service = _Service(
      state: ScooterState.hibernating,
      savedScooters: {'E0:23:A7:DF:93:53': SavedScooter(id: 'E0:23:A7:DF:93:53', name: 'Hubert')},
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(initialThemeMode: ThemeMode.light, child: MaterialApp(
        localizationsDelegates: [FlutterI18nDelegate(translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))],
        home: const SettingsScreen(),
      )),
    ));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SettingsScreen));
    expect(find.text(FlutterI18n.translate(context, 'ls_settings_scooter_asleep')), findsWidgets);
    for (final key in ['ls_keycard_title', 'ls_settings_auto_lock_title',
      'ls_settings_auto_hibernate_title', 'ls_settings_battery_keep_active_title',
      'ls_settings_alarm_title', 'ls_settings_alarm_honk_title',
      'ls_settings_apn_title', 'ls_settings_ota_title']) {
      final title = find.text(FlutterI18n.translate(context, key));
      await tester.scrollUntilVisible(title, 180, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final row = tester.widget<ListTile>(find.ancestor(of: title, matching: find.byType(ListTile)).first);
      expect(row.enabled, isFalse, reason: key);
      expect(row.onTap, isNull, reason: key);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    for (final dropdown in tester.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))) {
      expect(dropdown.onChanged, isNull);
    }
    // Auto-connect is stored on the scooter record, so it stays available.
    final autoConnect = find.text(FlutterI18n.translate(context, 'settings_scooter_auto_connect'));
    await tester.scrollUntilVisible(autoConnect, -180, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(autoConnect, findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.ancestor(
      of: autoConnect, matching: find.byType(SwitchListTile))).onChanged, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('extended reads are skipped while the scooter sleeps', () {
    final source = File('lib/stats/settings_screen.dart').readAsStringSync();
    expect(source, contains('!_isCurrent(_session) || _scooterAsleep) return;'));
  });
}
