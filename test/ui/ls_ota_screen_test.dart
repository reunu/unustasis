import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/ls_ota_screen.dart';
import '../../packages/scooter_flutter/test/update_controller_test.dart' as shared;

class ScreenService extends ChangeNotifier implements ScooterService {
  ScreenService(this.updateController);
  @override
  final UpdateController updateController;
  @override
  bool get connected => true;
  @override
  String get updateTargetName => 'Captured A';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget screen(ScreenService service, {String locale = 'en'}) => ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(localizationsDelegates: [
        FlutterI18nDelegate(
            translationLoader:
                FileTranslationLoader(fallbackFile: 'en', basePath: 'assets/i18n', forcedLocale: Locale(locale)))
      ], home: const LsOtaScreen()),
    );
void main() {
  testWidgets('screen detach/reattach retains actual shared download and install state', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller);
    h.provider.downloadGate = Completer();
    final step = shared.stepFor(shared.release('v2.0.0'));
    late Future<void> run;
    await tester.runAsync(() async {
      run = h.controller.executeStep(step);
      await shared.until(() => h.provider.urls.isNotEmpty);
    });
    await tester.pumpWidget(screen(service));
    await tester.pumpAndSettle();
    expect(h.controller.downloading, true);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(h.controller.downloading, true);
    await tester.pumpWidget(screen(service));
    await tester.pumpAndSettle();
    expect(h.controller.transfer.activeStep, same(step));
    await tester.runAsync(() async {
      h.provider.downloadGate!.complete(h.provider.response());
      await run;
    });
    await tester.pumpAndSettle();
    expect(find.text('Update installed'), findsOneWidget);
    expect(h.provider.urls.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
  testWidgets('unconfirmed installation displays captured target with English key fallback', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    h.repo.installPhase = null;
    await tester.runAsync(() async {
      final run = h.controller.executeStep(shared.stepFor(shared.release('v2.0.0')));
      await shared.until(() => h.controller.transfer.state == OtaTransferState.installing);
      h.devices['A']!.drop();
      await run;
      await h.connect('B');
    });
    final service = ScreenService(h.controller);
    await tester.pumpWidget(screen(service, locale: 'de'));
    await tester.pumpAndSettle();
    expect(find.text('Reconnect to Captured A to confirm the installation before starting another update.'),
        findsOneWidget);
    expect(find.text('ls_ota_awaiting_confirmation'), findsNothing);
    expect(h.controller.targetId, 'A');
    expect(h.repo.control.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
  testWidgets('cached Resume rejects session replacement before any START', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final original = h.repo;
    final step = shared.stepFor(shared.release('v2.0.0'));
    await tester.runAsync(() => File('${h.dir.path}/${step.asset.name}').writeAsBytes([1, 2, 3]));
    h.controller.transfer.activeStep = step;
    h.controller.transfer.state = OtaTransferState.failure;
    h.controller.transfer.resumable = true;
    h.cacheGate = Completer();
    final service = ScreenService(h.controller);
    await tester.pumpWidget(screen(service));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Resume')));
    await tester.pump();
    expect(h.controller.downloading, true);
    await tester.runAsync(() async {
      await h.connect('B');
      h.cacheGate!.complete();
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(h.controller.downloading, false);
    expect(original.control.writes, isEmpty);
    expect(h.repo.control.writes, isEmpty);
    expect(h.provider.urls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
  for (final id in ['A', 'B']) {
    testWidgets('mounted interrupted index gets a current $id plan without reopening', (tester) async {
      final h = shared.UpdateHarness();
      await tester.runAsync(h.init);
      final gate = Completer<List<FirmwareRelease>>();
      h.provider.indexGate = gate;
      late Future<void> run;
      await tester.runAsync(() async {
        run = h.controller.refresh();
        await shared.until(() => h.provider.channels.isNotEmpty);
      });
      final service = ScreenService(h.controller);
      await tester.pumpWidget(screen(service));
      await tester.pump();
      final mountedState = tester.state(find.byType(LsOtaScreen));
      await tester.runAsync(() async {
        h.devices['A']!.drop();
        h.autoReady = true;
        await h.connect(id);
        h.provider.indexGate = null;
        gate.complete([shared.release('v9.0.0')]);
      });
      for (var i = 0; i < 40 && h.controller.plan == null; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      expect(h.controller.phase, UpdatePlanPhase.ready);
      await tester.runAsync(() => run);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(LsOtaScreen)), same(mountedState));
      expect(h.controller.plan!.steps.first.release.tagName, 'v2.0.0');
      final install = find.widgetWithText(TextButton, 'Install');
      expect(install, findsOneWidget);
      expect(tester.widget<TextButton>(install).onPressed, isNotNull);
      expect(h.provider.channels.length, 2);
      expect(h.provider.urls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      await tester.runAsync(h.close);
    });
  }

  testWidgets('mounted recovered-index error remains retryable only by explicit Retry', (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final gate = Completer<List<FirmwareRelease>>();
    h.provider.indexGate = gate;
    late Future<void> run;
    await tester.runAsync(() async {
      run = h.controller.refresh();
      await shared.until(() => h.provider.channels.isNotEmpty);
    });
    final service = ScreenService(h.controller);
    await tester.pumpWidget(screen(service));
    await tester.pump();
    await tester.runAsync(() async {
      h.devices['A']!.drop();
      h.autoReady = true;
      await h.connect('B');
      h.provider.indexGate = null;
      h.provider.indexError = const UpdateHttpError(503, index: true);
      gate.complete([shared.release('v9.0.0')]);
    });
    for (var i = 0; i < 40 && h.controller.phase != UpdatePlanPhase.error; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(h.controller.phase, UpdatePlanPhase.error);
    await tester.runAsync(() => run);
    h.controller.sessionReady();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(h.provider.channels.length, 2);
    h.provider.indexError = null;
    await tester.runAsync(() => tester.tap(find.widgetWithText(TextButton, 'Retry')));
    for (var i = 0; i < 30 && h.controller.plan == null; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pumpAndSettle();
    expect(h.controller.phase, UpdatePlanPhase.ready);
    expect(find.widgetWithText(TextButton, 'Install'), findsOneWidget);
    expect(h.provider.channels.length, 3);
    expect(h.provider.urls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
}
