import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/home_screen.dart';
import 'package:unustasis/ui/theme/app_theme.dart';
import '../support/inline_asset_bundle.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  int? version;
  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async => version;
  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) async {
    version = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Blue extends Fake implements FlutterBluePlusMockable {}

class _Service extends ScooterService {
  _Service() : super(_Blue(), initializeRuntime: false);
  bool online = false;
  @override
  bool get connected => online;
  void connect() {
    online = true;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('automatic invitation waits for connection and a foreground home route', (tester) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    final preferences = _Preferences();
    SharedPreferencesAsyncPlatform.instance = preferences;
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    SharedPreferences.setMockInitialValues({});
    final service = _Service();
    addTearDown(service.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: EasyDynamicThemeWidget(
          child: MaterialApp(
        navigatorKey: nav,
        theme: unustasisLightTheme(),
        localizationsDelegates: [
          FlutterI18nDelegate(
              translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: const Locale('en')))
        ],
        home: const HomeScreen(forceOpen: true, batteryTrackerEnabled: true),
      )),
    ));
    await _pump(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(preferences.version, isNull);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other route'))));
    await _pump(tester);
    service.connect();
    await _pump(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(preferences.version, isNull);
    nav.currentState!.pop();
    await _pump(tester);
    service.refresh();
    await _pump(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.ensureVisible(find.text('Not now'));
    await _pump(tester);
    await tester.tap(find.text('Not now'));
    await _pump(tester);
    expect(preferences.version, 1);
    service.refresh();
    await _pump(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
