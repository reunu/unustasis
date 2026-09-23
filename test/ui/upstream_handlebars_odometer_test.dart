import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/domain/scooter_power_state.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/domain/scooter_vehicle_state.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/state/vehicle_status.dart';
import 'package:unustasis/state/scooter_identity.dart';
import 'package:unustasis/ui/screens/home_screen.dart';

class _StatusService extends ChangeNotifier implements ScooterService {
  @override
  bool connected = true;
  @override
  bool get scanning => false;
  @override
  ScooterState get state => connected ? ScooterState.parked : ScooterState.disconnected;
  @override
  ScooterVehicleState get vehicleState => ScooterVehicleState.parked;
  @override
  ScooterPowerState get powerState => ScooterPowerState.running;
  @override
  final vehicle = VehicleStatus()..handlebarsLocked = false;
  @override
  final identity = ScooterIdentity();
  void change({required bool connected, required bool? locked}) {
    this.connected = connected;
    vehicle.handlebarsLocked = locked;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected call: ${invocation.memberName}');
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('animated handlebar hint tracks known unlocked state at text scale $scale', (tester) async {
      final service = _StatusService();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
        value: service,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          localizationsDelegates: [
            FlutterI18nDelegate(
                translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: const Locale('en'),
            ))
          ],
          home: const Scaffold(body: SizedBox(width: 360, child: StatusText())),
        ),
      ));
      await tester.pumpAndSettle();
      final status = find.byType(StatusText);
      final hint = find.descendant(of: status, matching: find.byType(AnimatedSize));
      final initialHeight = tester.getSize(status).height;
      expect(hint, findsOneWidget);
      expect(find.bySemanticsLabel('Handlebars unlocked'), findsOneWidget);
      expect(find.bySemanticsLabel('Handlebars locked'), findsNothing);
      for (final state in [
        (connected: true, locked: true),
        (connected: true, locked: null),
        (connected: false, locked: false),
        (connected: false, locked: true),
        (connected: true, locked: false),
      ]) {
        service.change(connected: state.connected, locked: state.locked);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Handlebars unlocked'),
            state.connected && state.locked == false ? findsOneWidget : findsNothing);
        expect(find.bySemanticsLabel('Handlebars locked'), findsNothing);
        if (state.connected) {
          expect(tester.getSize(status).height <= initialHeight, isTrue);
        }
      }
      service.vehicle.cancelSubscriptions();
      service.change(connected: true, locked: service.vehicle.handlebarsLocked);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Handlebars unlocked'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  test('odometer UI preserves shared owner and refreshes only the visible screen', () {
    final screen = File('lib/ui/screens/stats/scooter_screen.dart').readAsStringSync();
    expect(
        'connected ? context.select<ScooterService, int?>((service) => service.odometerMeters) : null'
            .allMatches(screen),
        hasLength(2));
    expect('if (odometerMeters != null)'.allMatches(screen), hasLength(2));
    expect(screen, contains('Timer.periodic(const Duration(seconds: 30)'));
    expect(screen, contains('if (!mounted || ModalRoute.of(context)?.isCurrent != true) return'));
    expect(screen, contains('_odometerRefreshTimer?.cancel()'));
    expect(screen, isNot(contains('readOdometer(')));
    final facade = File('lib/scooter_service.dart').readAsStringSync();
    expect(facade, contains('if (connected) _telemetry.refreshOdometer()'));
    expect(File('lib/background/translate_static.dart').readAsStringSync(),
        contains("'lock_state_locked': 'Handlebar locked'"));
  });
}
