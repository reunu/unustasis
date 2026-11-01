import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/service/battery_onboarding_preferences.dart';
import 'package:unustasis/ui/dialogs/battery_feature_announcement.dart';
import 'package:unustasis/ui/theme/app_theme.dart';
import '../support/inline_asset_bundle.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  int? version;
  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async => version;
  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) async {
    expect(key, batteryFeatureOnboardingVersionKey);
    version = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw TestFailure('Unexpected persistence: ${invocation.memberName}');
}

void main() {
  late _Preferences preferences;
  late SharedPreferencesAsyncPlatform? previous;
  var connected = true;
  var opened = 0;
  setUp(() {
    previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = preferences = _Preferences();
    connected = true;
    opened = 0;
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

  Future<void> mount(WidgetTester tester, {bool enabled = true, double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: unustasisLightTheme(),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: const Locale('en')))
      ],
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showBatteryFeatureAnnouncement(context,
                        enabled: enabled,
                        canShow: () => connected,
                        openTracker: () async {
                          opened++;
                        }),
                    child: const Text('Show'),
                  ))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  testWidgets('once-only introduction changes no battery data', (tester) async {
    await mount(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(preferences.version, isNull);
    expect(opened, 0);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(preferences.version, currentBatteryFeatureOnboardingVersion);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
  testWidgets('add battery opens the native flow without signup or upload', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Add a battery'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(preferences.version, currentBatteryFeatureOnboardingVersion);
  });
  testWidgets('unavailable registration defers introduction', (tester) async {
    await mount(tester, enabled: false);
    expect(find.byType(BottomSheet), findsNothing);
    expect(preferences.version, isNull);
  });
  testWidgets('disconnected introduction is deferred without marking seen', (tester) async {
    connected = false;
    await mount(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(preferences.version, isNull);
  });
  testWidgets('disconnect during introduction cannot open a later flow', (tester) async {
    await mount(tester);
    connected = false;
    await tester.tap(find.text('Add a battery'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(preferences.version, isNull);
  });
  testWidgets('large text introduction can be scrolled to dismiss', (tester) async {
    await mount(tester, scale: 2);
    await tester.ensureVisible(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
