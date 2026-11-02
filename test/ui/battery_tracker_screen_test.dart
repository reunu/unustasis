import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:scooter_core/battery_identity.dart';
import 'package:unustasis/ui/screens/battery_tracker_screen.dart';
import 'package:unustasis/service/battery_handoff_client.dart';
import 'package:unustasis/ui/theme/app_theme.dart';
import 'package:unustasis/ui/widgets/battery_tracking_intro.dart';

import '../support/inline_asset_bundle.dart';
import '../support/persistence_fakes.dart';

void main() {
  final battery = BatteryIdentity(
      serialNumber: 'T-UNU22205090007', source: BatteryIdentitySource.nfc, checkedAt: DateTime.utc(2026, 10, 27));
  final other = BatteryIdentity(
      serialNumber: '00000000000000AB',
      source: BatteryIdentitySource.ble,
      checkedAt: DateTime.utc(2026, 10, 27),
      slot: 1);
  final handoffUri =
      Uri.https('sunshine.rescoot.org', '/battery_tracker/handoff').replace(fragment: 'code=${'a' * 43}');
  late List<BatteryIdentity> shared;
  Future<BatteryHandoff> prepareHandoff(BatteryIdentity identity) async {
    shared.add(identity);
    return BatteryHandoff(uri: handoffUri, expiresAt: DateTime.now().add(const Duration(minutes: 10)));
  }

  late MemoryPreferences preferences;
  late SharedPreferencesAsyncPlatform? previous;

  setUp(() {
    shared = [];
    previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = preferences = MemoryPreferences();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

  Future<void> pump(
    WidgetTester tester,
    BatteryTrackerScreen screen, {
    Size size = const Size(1000, 1800),
    double textScale = 1,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.light ? unustasisLightTheme() : unustasisDarkTheme(),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader: InlineFileTranslationLoader(basePath: 'assets/i18n', forcedLocale: locale))
      ],
      home: BatteryTrackerScreen(
        readBluetooth: screen.readBluetooth,
        readNfc: screen.readNfc,
        openBrowser: screen.openBrowser,
        prepareHandoff: screen.prepareHandoff ?? prepareHandoff,
        bluetoothSupported: screen.bluetoothSupported,
        startWithScan: screen.startWithScan,
        registrationEnabled: screen.registrationEnabled,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> read(WidgetTester tester, String source) async {
    await tap(tester, find.byKey(const ValueKey('add-battery')));
    await tap(tester, find.byKey(ValueKey('battery-source-$source')));
  }

  testWidgets('registration reuses the existing unu pack graphic throughout identification', (tester) async {
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery], registrationEnabled: true));
    void expectPackAsset() {
      final image =
          tester.widget<Image>(find.descendant(of: find.byType(BatteryRegistrationArt), matching: find.byType(Image)));
      expect((image.image as AssetImage).assetName, 'images/battery/batt_full.webp');
    }

    expectPackAsset();
    await tap(tester, find.byKey(const ValueKey('add-battery')));
    expectPackAsset();
    await tap(tester, find.byKey(const ValueKey('battery-source-bluetooth')));
    expectPackAsset();
  });

  testWidgets('owner-first welcome has one primary action and no premature email signup', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [],
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    expect(find.text('Your batteries.\nA little peace of mind.'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Add a battery'), findsOneWidget);
    expect(find.text('Join the shared tracker'), findsNothing);
    expect(find.text('Confirm your email'), findsNothing);
    expect(opened, isEmpty);
    await tap(tester, find.byKey(const ValueKey('add-battery')));
    expect(find.byKey(const ValueKey('battery-source-bluetooth')), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('scan then explicit label match then sharing consent precede browser handoff', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [],
            readNfc: () async => battery,
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'nfc');
    expect(find.text(battery.serialNumber), findsOneWidget);
    expect(find.text('Is this your battery?'), findsOneWidget);
    expect(find.byKey(const ValueKey('battery-register-continue')), findsNothing);
    expect(opened, isEmpty);
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    expect(find.byKey(const ValueKey('battery-sharing-disclosure')), findsOneWidget);
    expect(find.textContaining('sunshine.rescoot.org'), findsOneWidget);
    expect(opened, isEmpty);
    expect(shared, isEmpty);
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(shared, [battery]);
    expect(opened, [handoffUri]);
    expect(opened.single.toString(), isNot(contains(battery.serialNumber)));
    expect(opened.single.hasQuery, isFalse);
    expect(opened.single.fragment, 'code=${'a' * 43}');
    expect(find.text('One last step in your browser.'), findsOneWidget);
    expect(find.textContaining('only registered after you confirm'), findsOneWidget);
    expect(find.textContaining('registered successfully'), findsNothing);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
  });

  testWidgets('back from sharing requires label confirmation again without uploading', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery],
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tap(tester, find.byType(BackButton));
    expect(find.text('Is this your battery?'), findsOneWidget);
    expect(find.byKey(const ValueKey('battery-register-continue')), findsNothing);
    await tap(tester, find.byType(BackButton));
    expect(find.text(battery.serialNumber), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('multiple readings register only the explicitly selected and checked battery', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery, other],
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'bluetooth');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('battery-label-verification'))).onPressed, isNull);
    await tap(tester, find.byKey(ValueKey('battery-reading-${other.serialNumber}')));
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    expect(find.text(other.serialNumber), findsOneWidget);
    expect(find.text(battery.serialNumber), findsNothing);
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(shared, [other]);
    expect(opened.single, handoffUri);
  });

  testWidgets('mismatched serial restarts scanning, readings never become an inventory', (tester) async {
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery]));
    await read(tester, 'bluetooth');
    await tap(tester, find.text("Doesn't match? Read again"));
    expect(find.text(battery.serialNumber), findsNothing);
    await tap(tester, find.byKey(const ValueKey('battery-source-bluetooth')));
    expect(find.text(battery.serialNumber), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery]));
    expect(find.text(battery.serialNumber), findsNothing);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
  });

  testWidgets('NFC is first when BLE is unavailable and only BLE has firmware badge', (tester) async {
    await pump(tester,
        BatteryTrackerScreen(readBluetooth: () async => [], readNfc: () async => battery, bluetoothSupported: false));
    await tap(tester, find.byKey(const ValueKey('add-battery')));
    final nfc = find.byKey(const ValueKey('battery-source-nfc'));
    final ble = find.byKey(const ValueKey('battery-source-bluetooth'));
    expect(tester.getTopLeft(nfc).dy, lessThan(tester.getTopLeft(ble).dy));
    expect(tester.widget<ListTile>(ble).enabled, isFalse);
    expect(find.descendant(of: ble, matching: find.text('Librescoot')), findsOneWidget);
    expect(find.descendant(of: nfc, matching: find.text('Librescoot')), findsNothing);
    expect(find.textContaining('1.4'), findsNothing);
  });

  testWidgets('management sends no serial even after returning from a read', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery],
            registrationEnabled: true,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    await read(tester, 'bluetooth');
    await tap(tester, find.byType(BackButton));
    await tap(tester, find.byType(BackButton));
    await tap(tester, find.byKey(const ValueKey('manage-battery-tracker')));
    expect(shared, isEmpty);
    expect(opened, [batteryTrackerRegistrationsUri()]);
    expect(opened.single.hasQuery, isFalse);
  });

  testWidgets('closed rollout gate allows local checks but not sharing or management', (tester) async {
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery],
            registrationEnabled: false,
            openBrowser: (uri) async {
              opened.add(uri);
              return true;
            }));
    expect(find.byKey(const ValueKey('manage-battery-tracker')), findsNothing);
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('battery-register-continue'))).onPressed, isNull);
    expect(opened, isEmpty);
    expect(shared, isEmpty);
  });

  testWidgets('empty and failed reads retain the method choices for retry', (tester) async {
    var calls = 0;
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async {
      if (calls++ == 0) return [];
      throw StateError('unavailable');
    }));
    await read(tester, 'bluetooth');
    expect(find.textContaining('No battery serials'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('battery-source-bluetooth')));
    expect(find.textContaining('The connection was interrupted'), findsOneWidget);
    expect(find.byKey(const ValueKey('battery-label-verification')), findsNothing);
  });

  testWidgets('cancelled NFC read cannot advance a later screen', (tester) async {
    final reading = Completer<BatteryIdentity>();
    await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [], readNfc: () => reading.future));
    await tap(tester, find.byKey(const ValueKey('add-battery')));
    await tester.tap(find.byKey(const ValueKey('battery-source-nfc')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    reading.complete(battery);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-battery')), findsOneWidget);
    expect(find.text(battery.serialNumber), findsNothing);
  });

  testWidgets('browser failure remains retryable without pretending registration succeeded', (tester) async {
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery], registrationEnabled: true, openBrowser: (_) async => false));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(find.textContaining('Could not open your browser'), findsOneWidget);
    expect(find.text('One last step in your browser.'), findsNothing);
    expect(find.byKey(const ValueKey('battery-register-continue')), findsOneWidget);
  });

  testWidgets('failed browser launch reuses the prepared handoff on explicit retry', (tester) async {
    var launches = 0;
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [battery],
          registrationEnabled: true,
          openBrowser: (_) async => ++launches > 1,
        ));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(shared, [battery]);
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(shared, [battery]);
    expect(launches, 2);
    expect(find.text('One last step in your browser.'), findsOneWidget);
    await tap(tester, find.text('Return to registration'));
    expect(shared, [battery]);
    expect(launches, 3);
  });

  testWidgets('cancelled handoff cannot launch the browser or restore sharing', (tester) async {
    final handoff = Completer<BatteryHandoff>();
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [battery],
          registrationEnabled: true,
          prepareHandoff: (_) => handoff.future,
          openBrowser: (uri) async {
            opened.add(uri);
            return true;
          },
        ));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tester.tap(find.byKey(const ValueKey('battery-register-continue')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('battery-register-continue'))).onPressed, isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    handoff.complete(await prepareHandoff(battery));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Is this your battery?'), findsOneWidget);
  });

  testWidgets('failed handoff never falls back to a serial URL or retries automatically', (tester) async {
    var attempts = 0;
    final opened = <Uri>[];
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [battery],
          registrationEnabled: true,
          prepareHandoff: (_) async {
            attempts++;
            throw const BatteryHandoffException(BatteryHandoffFailure.rateLimited);
          },
          openBrowser: (uri) async {
            opened.add(uri);
            return true;
          },
        ));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(attempts, 1);
    expect(opened, isEmpty);
    expect(find.textContaining('Too many attempts'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(attempts, 1);
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    expect(attempts, 2);
  });

  testWidgets('adding another battery cancels a pending browser return without leaving a busy screen', (tester) async {
    final opening = Completer<bool>();
    var launches = 0;
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [battery],
          registrationEnabled: true,
          openBrowser: (_) => ++launches == 1 ? Future.value(true) : opening.future,
        ));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
    await tester.tap(find.text('Return to registration'));
    await tester.pump();
    await tester.tap(find.text('Add another battery'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('battery-source-bluetooth')), findsOneWidget);
    opening.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('One last step in your browser.'), findsNothing);
  });

  testWidgets('disposed screen ignores a completed handoff', (tester) async {
    final handoff = Completer<BatteryHandoff>();
    var launches = 0;
    await pump(
        tester,
        BatteryTrackerScreen(
          readBluetooth: () async => [battery],
          registrationEnabled: true,
          prepareHandoff: (_) => handoff.future,
          openBrowser: (_) async {
            launches++;
            return true;
          },
        ));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tester.tap(find.byKey(const ValueKey('battery-register-continue')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    handoff.complete(await prepareHandoff(battery));
    await tester.pumpAndSettle();
    expect(launches, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late browser completion cannot resurrect a dismissed sharing step', (tester) async {
    final opening = Completer<bool>();
    await pump(
        tester,
        BatteryTrackerScreen(
            readBluetooth: () async => [battery], registrationEnabled: true, openBrowser: (_) => opening.future));
    await read(tester, 'bluetooth');
    await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
    await tester.tap(find.byKey(const ValueKey('battery-register-continue')));
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tap(tester, find.byType(BackButton));
    opening.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('battery-source-bluetooth')), findsOneWidget);
    expect(find.text(battery.serialNumber), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('registration has readable contrast and accessible targets ${brightness.name}', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [battery], registrationEnabled: true),
            brightness: brightness);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await read(tester, 'bluetooth');
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  for (final locale in [const Locale('en'), const Locale('de')]) {
    testWidgets('hash capability badge ${locale.languageCode}', (tester) async {
      await pump(tester, BatteryTrackerScreen(readBluetooth: () async => [], startWithScan: true), locale: locale);
      expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message?.contains('(hash=1)') ?? false)), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message?.contains('battery=1') ?? false)), findsNothing);
    });
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('all steps fit narrow large text ${locale.languageCode} ${brightness.name}', (tester) async {
        await pump(
            tester,
            BatteryTrackerScreen(
                readBluetooth: () async => [battery], registrationEnabled: true, openBrowser: (_) async => true),
            size: const Size(320, 568),
            textScale: 2,
            locale: locale,
            brightness: brightness);
        expect(tester.takeException(), isNull);
        await read(tester, 'bluetooth');
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const ValueKey('battery-label-verification')));
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const ValueKey('battery-register-continue')));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('battery-register-continue')), findsNothing);
      });
    }
  }
}
