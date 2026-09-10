import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/scooter_service.dart';
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
    for (final key in ['ls_settings_auto_lock_title', 'ls_settings_auto_hibernate_title',
      'ls_scheduled_hibernation_title', 'ls_keycard_title', 'ls_settings_ota_title',
      'ls_settings_update_mode_title', 'ls_settings_apn_title']) {
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
}
