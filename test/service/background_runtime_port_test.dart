import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/screens/stats/settings_screen.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/persistence_fakes.dart';

void main() {
  test('disabled Android startup has no Bluetooth owner and explicit off stops temporary service', () {
    final source = File('lib/background/bg_service.dart').readAsStringSync();
    expect(source, contains('late FlutterBluePlusMockable fbp;'));
    expect(source, contains('late ScooterService scooterService;'));
    final setup = source.substring(
        source.indexOf('Future<void> setupBackgroundService()'), source.indexOf("@pragma('vm:entry-point')"));
    expect(setup, contains('autoStart: backgroundScanEnabled'));
    expect(setup, isNot(contains('service.startService()')));
    final start = source.substring(source.indexOf('void onStart('));
    final idle = start.indexOf('if (!backgroundScanEnabled && !pendingWidgetAction)');
    expect(idle, greaterThan(0));
    expect(start.indexOf('service.stopSelf();', idle),
        lessThan(start.indexOf('_initializeScooterService(allowAutomaticActions: backgroundScanEnabled)')));
    final initialize = source.substring(source.indexOf('void _initializeScooterService('),
        source.indexOf('Future<void> setupBackgroundService()'));
    expect(initialize, contains('allowAutomaticActions: allowAutomaticActions'));
    final enable = source.substring(source.indexOf('void _enableScanning()'), source.indexOf('void _disableScanning('));
    expect(enable.indexOf('scooterService.setAutomaticActionsAllowed(true)'),
        lessThan(enable.indexOf('scooterService.rssiTimer.start()')));
    expect(start, contains('_disableScanning(stopService: true)'));
    final disable = source.substring(
        source.indexOf('void _disableScanning('), source.indexOf('Future<void> _checkPendingWidgetAction'));
    expect(disable, contains('scooterService.setAutomaticActionsAllowed(false)'));
    expect(disable, contains('scooterService.disconnectAndClearDevice()'));
    expect(disable, contains('_androidServiceInstance?.stopSelf()'));
  });

  test('both disconnected Android widget buttons route Scan to reconnect, never unlock', () {
    final native =
        File('android/app/src/main/kotlin/de/freal/unustasis/HomeWidgetGlanceAppWidget.kt').readAsStringSync();
    expect('actionRunCallback<ConnectAction>()'.allMatches(native), hasLength(2));
    expect(native, contains('Uri.parse("unustasis://scan")'));
    final dart = File('lib/background/widget_handler.dart').readAsStringSync();
    expect(dart, contains('action = bgScanEnabled ? null : "connect"'));
    // Already-running services must not wait for the 35-second recovery timer.
    final service = File('lib/background/bg_service.dart').readAsStringSync();
    expect(service, contains('service.on("connect").listen((data) async => executeWidgetAction("connect"))'));
    expect(dart.indexOf('await prefs.setString("pendingWidgetActionName", action)'),
        lessThan(dart.indexOf('await prefs.setBool("pendingWidgetAction", true)')));
    // iOS presents explicit Lock/Unlock rather than a misleading Scan button.
    final ios = File('ios/ScooterWidget/ScooterWidget.swift').readAsStringSync();
    expect(ios, contains('action: isLocked ? "unlock" : "lock"'));
    expect(ios, contains('isLocked ? "Unlock" : "Lock"'));
  });

  test('large Android widget accessibility describes the selected lock unlock or reconnect action', () {
    final native = File('android/app/src/main/kotlin/de/freal/unustasis/HomeWidgetGlanceAppWidget.kt').readAsStringSync();
    final button = native.substring(native.indexOf('contentDescription = if (enabled && locked == false)'));
    expect(button, contains('''contentDescription = if (enabled && locked == false) {
                                    "Lock scooter"
                                } else if (enabled && locked == true) {
                                    "Unlock scooter"
                                } else {
                                    "Reconnect scooter"
                                }'''));
    expect(button, contains('''if(locked == false && enabled){
                                    actionRunCallback<LockAction>()
                                } else if (locked == true && enabled){
                                    actionRunCallback<UnlockAction>()
                                } else {
                                    actionRunCallback<ConnectAction>()'''));
  });

  test('Settings persist and restart before enable event using fresh cross-isolate scan preference', () {
    final source = File('lib/ui/screens/stats/settings_screen.dart').readAsStringSync();
    final persist = source.indexOf('await prefs.setBool("backgroundScan", value)');
    final restart = source.indexOf('if (value) await backgroundService.startService()');
    expect(persist, greaterThan(0));
    expect(restart, greaterThan(persist));
    expect(source.indexOf('backgroundService.invoke("update"'), greaterThan(restart));
    for (final file in ['lib/background/bg_service.dart', 'lib/background/widget_handler.dart']) {
      final source = File(file).readAsStringSync();
      expect(source, contains('await SharedPreferencesAsync().getBool("backgroundScan")'));
      expect(source, isNot(contains('(await SharedPreferences.getInstance()).getBool("backgroundScan")')));
    }
  });

  test('manifest removes only unused geolocator foreground type and preserves app IDs', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('com.baseflow.geolocator.GeolocatorLocationService'));
    expect(manifest, contains('tools:remove="android:foregroundServiceType"'));
    expect(manifest, contains('android:foregroundServiceType="connectedDevice"'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_LOCATION')));
    expect(File('lib/background/widget_handler.dart').readAsStringSync(), contains('group.de.freal.unustasis'));
  });

  testWidgets('background warning retains battery and accidental activation guidance without pairing-loss claim',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n',
          fallbackFile: 'en',
          forcedLocale: const Locale('en'),
        ))
      ],
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();
    // The dialog is context-only; do not initialize the Settings platform owners.
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = MemoryPreferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    final dynamic settings = const SettingsScreen().createState();
    settings.showBackgroundScanWarning(context);
    await tester.pumpAndSettle();
    expect(find.text(FlutterI18n.translate(context, 'bgscan_warning_lostpairing')), findsNothing);
    for (final key in ['bgscan_warning_battery', 'bgscan_warning_accidentalturnon']) {
      expect(find.text(FlutterI18n.translate(context, key)), findsOneWidget);
    }
    expect(find.byIcon(Icons.battery_alert_outlined), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
