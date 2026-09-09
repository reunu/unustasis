import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/dialogs/seat_warning.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

// Exercise the actual home confirmation/dispatch and BLE runtime, replacing
// only native BLE and the app facade's unrelated plugin/storage dependencies.
import '../../packages/scooter_flutter/test/scooter_actions_test.dart' as runtime;

class _Service extends Fake implements ScooterService {
  _Service(this.h, this.transportZone);
  final Zone transportZone;
  final runtime.Harness h;
  @override
  ScooterActions get actions => h.actions;
  @override
  VehicleStatus get vehicle => h.telemetry.vehicle;
  @override
  Future<void> lock({bool checkHandlebars = true, bool confirmOpenSeat = false,
      EventSource source = EventSource.app}) =>
      transportZone.run(() => actions.lock(checkHandlebars: false, confirmOpenSeat: confirmOpenSeat, source: source));
}

Future<void> _hold(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.descendant(of: find.byType(ScooterPowerButton), matching: find.byType(GestureDetector)).first));
  await tester.pump(const Duration(milliseconds: 100)); await tester.pump();
  await tester.pump(const Duration(milliseconds: 900)); await gesture.up(); await tester.pump();
}

void main() {
  for (final scenario in ['confirm', 'cancel', 'first-fails', 'second-fails', 'replace', 'replace-same-id', 'replace-after-first', 'same-id-after-first', 'disconnect-after-first', 'closed']) {
    testWidgets('home seatbox confirmation: $scenario', (tester) async {
      late runtime.Harness h;
      late Zone transportZone;
      await tester.runAsync(() async {
        transportZone = Zone.current;
        h = runtime.Harness(FakeAsync()); await runtime.settleTransport(); h.trace.clear();
      });
      h.telemetry.vehicle.seatClosed = scenario == 'closed';
      final service = _Service(h, transportZone);
      final ackGate = Completer<void>();
      var writes = 0;
      h.wire.onWrite = (command) async {
        if (command != lockCommand) return;
        writes++;
        if (scenario == 'first-fails') throw StateError('first write failed');
        if (writes == 1 && scenario.endsWith('after-first')) {
          if (scenario == 'disconnect-after-first') {
            h.device.drop();
          } else {
            if (scenario == 'same-id-after-first') h.session.connected = false;
            h.connect(scenario == 'same-id-after-first' ? 'A' : 'B');
          }
          return;
        }
        if (writes == 2) {
          await ackGate.future;
          if (scenario == 'second-fails') throw StateError('second write failed');
        }
      };
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: [FlutterI18nDelegate(translationLoader: FileTranslationLoader(
          basePath: 'assets/i18n', fallbackFile: 'en', forcedLocale: const Locale('en')))],
        home: Scaffold(body: Builder(builder: (context) => Center(child: ScooterPowerButton(
          action: () async { await lockWithSeatConfirmation(context, service); },
          icon: Icons.lock_outline, label: 'Lock',
        )))),
      ));
      await tester.pumpAndSettle(); await _hold(tester); await tester.pump(const Duration(seconds: 7));
      if (scenario != 'closed') {
        expect(find.byType(SeatWarning), findsOneWidget); expect(h.trace, isEmpty);
        if (scenario == 'replace' || scenario == 'replace-same-id') {
          await tester.runAsync(() async { if (scenario == 'replace-same-id') h.session.connected = false; h.connect(scenario == 'replace' ? 'B' : 'A'); await runtime.settleTransport(); h.trace.clear(); });
        }
        await tester.tap(find.text(scenario == 'cancel' ? 'Cancel' : 'Lock anyways'));
      }
      for (var i = 0; i < 5; i++) { await tester.pump(); await tester.runAsync(runtime.settleTransport); }
      await tester.pump(const Duration(milliseconds: 300));
      final doubleLock = ['confirm', 'second-fails'].contains(scenario);
      if (doubleLock) {
        expect(writes, 2, reason: h.trace.toString());
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _hold(tester); // Pending second write suppresses duplicate intent.
        expect(writes, 2);
      }
      ackGate.complete(); await tester.runAsync(runtime.settleTransport); await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.trace.where((e) => e.endsWith(lockCommand)), hasLength(doubleLock ? 2 : (['closed', 'first-fails'].contains(scenario) || scenario.endsWith('after-first')) ? 1 : 0));
      expect(h.trace.where((e) => e.contains('force-lock') || e.contains('cap:') || e.contains('ignore-seatbox')), isEmpty);
      expect(h.effects.events, hasLength(['confirm', 'closed'].contains(scenario) ? 1 : 0));
      if (scenario == 'confirm') expect(find.text('Lock requests sent. Check the scooter’s status.'), findsOneWidget);
      if (['first-fails', 'second-fails'].contains(scenario) || scenario.endsWith('after-first')) expect(find.textContaining('The first request may already'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async { h.dispose(); await runtime.settleTransport(); });
    });
  }
}
