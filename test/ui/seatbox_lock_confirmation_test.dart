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
  Future<void> lock({bool checkHandlebars = true, bool ignoreSeatbox = false,
      EventSource source = EventSource.app}) =>
      transportZone.run(() => actions.lock(checkHandlebars: false, ignoreSeatbox: ignoreSeatbox, source: source));
}

Future<void> _hold(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byType(ElevatedButton)));
  await tester.pump(const Duration(milliseconds: 100)); await tester.pump();
  await tester.pump(const Duration(milliseconds: 900)); await gesture.up(); await tester.pump();
}

void main() {
  for (final scenario in ['confirm', 'cancel', 'unsupported', 'unknown', 'replace', 'closed']) {
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
      h.wire.onWrite = (command) async {
        if (command == 'cap:lock') {
          h.wire.reply(scenario == 'unsupported' ? 'cap:lock:count:0' : 'cap:lock:count:1');
          if (scenario != 'unsupported') h.wire.reply('cap:lock:ignore-seatbox');
        }
        if (command == 'lock:ignore-seatbox') {
          await ackGate.future;
          h.wire.reply(scenario == 'unknown' ? 'lock:error:unknown-outcome' : 'lock:accepted');
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
        if (scenario == 'replace') {
          await tester.runAsync(() async { h.connect('B'); await runtime.settleTransport(); h.trace.clear(); });
        }
        await tester.tap(find.text(scenario == 'cancel' ? 'Cancel' : 'Lock anyways'));
      }
      for (var i = 0; i < 5; i++) { await tester.pump(); await tester.runAsync(runtime.settleTransport); }
      await tester.pump(const Duration(milliseconds: 300));
      final override = ['confirm', 'unknown'].contains(scenario);
      if (override) {
        expect(h.trace.where((e) => e == 'A:lock:ignore-seatbox'), hasLength(1), reason: h.trace.toString());
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _hold(tester); // A pending ACK must not issue a second request.
        expect(h.trace.where((e) => e == 'A:lock:ignore-seatbox'), hasLength(1));
      }
      ackGate.complete(); await tester.runAsync(runtime.settleTransport); await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.trace.where((e) => e.contains('scooter:state lock')), hasLength(scenario == 'closed' ? 1 : 0));
      expect(h.trace.where((e) => e.contains('lock:ignore-seatbox')), hasLength(override ? 1 : 0));
      expect(h.trace.where((e) => e.contains('force-lock')), isEmpty);
      if (scenario == 'confirm') expect(find.text('Shutdown request accepted. Check the scooter’s lock status.'), findsOneWidget);
      if (scenario == 'unknown') expect(find.text('Lock request outcome unknown. Check the scooter’s status before trying again.'), findsOneWidget);
      if (scenario == 'unsupported') expect(find.textContaining('This firmware does not support'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async { h.dispose(); await runtime.settleTransport(); });
    });
  }
}
