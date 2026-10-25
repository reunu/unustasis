import 'dart:async';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  _Preferences({required this.biometrics});
  final bool biometrics;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async => key == 'biometrics' && biometrics;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Blue extends Fake implements FlutterBluePlusMockable {}

class _Service extends ScooterService {
  _Service() : super(_Blue(), initializeRuntime: false);
  int starts = 0;

  @override
  Future<List<String>> getSavedScooterIds({bool onlyAutoConnect = false}) async => ['saved-scooter'];

  @override
  void start({bool restart = true}) => starts++;
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final scenario in ['success', 'cancel', 'exception', 'disabled', 'dispose']) {
    testWidgets('startup authentication: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final oldPreferences = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance = _Preferences(biometrics: scenario != 'disabled');
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = oldPreferences);
      final auth = Completer<bool>();
      final retry = Completer<bool>();
      var attempts = 0;
      final platformCalls = <String>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/local_auth'), (call) async {
        if (call.method == 'authenticate') {
          attempts++;
          return attempts == 1 ? auth.future : retry.future;
        }
        return true;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call.method);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/local_auth'), null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final service = _Service();
      addTearDown(service.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service,
        child: EasyDynamicThemeWidget(child: MaterialApp(
          navigatorKey: nav,
          localizationsDelegates: [FlutterI18nDelegate(translationLoader: FileTranslationLoader(
            basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))],
          home: const HomeScreen(),
        )),
      ));
      await _pump(tester);
      expect(service.starts, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(attempts, scenario == 'disabled' ? 0 : 1);
      if (scenario == 'disabled') {
        expect(service.optionalAuth, isTrue);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      } else {
        expect(service.optionalAuth, isFalse);
        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        if (scenario == 'dispose') {
          await tester.pumpWidget(const SizedBox());
        }
        if (scenario == 'exception') {
          auth.completeError(PlatformException(code: 'NotAvailable'));
        } else {
          auth.complete(scenario == 'success' || scenario == 'dispose');
        }
        await _pump(tester);
        if (scenario == 'cancel' || scenario == 'exception') {
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(nav.currentState!.canPop(), isFalse);
          expect(find.text('Authentication failed'), findsOneWidget);
          expect(find.byIcon(Icons.settings_outlined), findsNothing);
          expect(service.optionalAuth, isFalse);
          await tester.tap(find.text('Try again'));
          await _pump(tester);
          expect(attempts, 2);
          expect(find.byType(FilledButton), findsNothing);
          expect(service.optionalAuth, isFalse);
          retry.complete(true);
          await _pump(tester);
        }
        if (scenario != 'dispose') {
          expect(service.optionalAuth, isTrue);
          expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
          expect(find.text('Try again'), findsNothing);
        } else {
          expect(service.optionalAuth, isFalse);
        }
      }
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
