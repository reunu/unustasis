import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
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
  _Service({required this.connected});
  @override
  final bool connected;
  final Object _token = Object();
  @override
  Object? get connectionToken => connected ? _token : null;
  @override
  final ScooterState? state = null;
  @override
  final identity = ScooterIdentity()..isLibrescoot = false;
  @override
  final vehicle = VehicleStatus();
  @override
  bool get autoUnlock => true;
  @override
  bool get otaAvailable => false;
  @override
  String? get currentScooterId => connected ? 'AA:BB' : null;
  @override
  int get autoUnlockThreshold => -65;
  @override
  bool get openSeatOnUnlock => false;
  @override
  bool get hazardLocking => false;
  @override
  Map<String, SavedScooter> get savedScooters => const {};
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw TestFailure('Unexpected scooter access: ${invocation.memberName}');
}

Widget _screen(ScooterService service) => ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(
        initialThemeMode: ThemeMode.light,
        child: MaterialApp(
          localizationsDelegates: [
            FlutterI18nDelegate(
                translationLoader: FileTranslationLoader(
                    basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en'))),
          ],
          home: const SettingsScreen(),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _Preferences();
  });

  testWidgets('disconnected slider keeps the last value but dims it and explains the link', (tester) async {
    final service = _Service(connected: false)
      ..identity.rssi = -70
      ..identity.name = 'Hubert';
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Not connected to Hubert — move closer to the scooter'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue, -70);
    final theme = tester.widget<SliderTheme>(find.byType(SliderTheme).first);
    expect(theme.data.secondaryActiveTrackColor, isNotNull);
  });

  testWidgets('connected slider shows the scooter name and live signal strength', (tester) async {
    final service = _Service(connected: true)
      ..identity.rssi = -60
      ..identity.name = 'Hubert';
    addTearDown(service.dispose);
    await tester.pumpWidget(_screen(service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(Slider), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Connected to Hubert — signal strength -60 dBm'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue, -60);
  });
}
