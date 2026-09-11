import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';
import 'package:unustasis/ui/screens/ls_ota_screen.dart';

import '../../packages/scooter_flutter/test/navigation_runtime_test.dart' as transport;
import '../../packages/scooter_flutter/test/update_controller_test.dart' as shared;
import '../support/persistence_fakes.dart';

class _Storage extends Fake implements ScooterStorage {
  @override
  Map<String, SavedScooter> scooters = {
    'A': SavedScooter(id: 'A', name: 'Unustasis Alpha', color: 1),
    'B': SavedScooter(id: 'B', name: 'Current Beta', color: 2),
  };
}

Widget _screen(ScooterService service, String locale) => ChangeNotifierProvider<ScooterService>.value(
  value: service,
  child: MaterialApp(localizationsDelegates: [
    FlutterI18nDelegate(translationLoader: FileTranslationLoader(
      fallbackFile: 'en', basePath: 'assets/i18n', forcedLocale: Locale(locale))),
  ], home: const LsOtaScreen()),
);

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = MemoryPreferences());
  for (final locale in ['en', 'de']) {
    testWidgets('Unustasis $locale cold A adoption blocks B then confirms A without firmware resend', (tester) async {
      final h = shared.UpdateHarness();
      await tester.runAsync(h.init);
      final store = _Storage();
      final service = ScooterService(transport.Bluetooth(), storage: store, initializeRuntime: false);
      final updates = service.updateController;
      // Use actual facade name composition and controller, but explicit fake
      // transport bindings rather than startup, network or native BLE effects.
      updates.bind(h.session.currentConnection!, h.repo);
      h.repo.probePhase = 1;
      final captures = <String?>[];
      updates.transfer.addListener(() => captures.add(service.updateTargetName));
      await tester.runAsync(updates.refresh);
      expect(captures, isNotEmpty);
      expect(captures.every((name) => name == 'Unustasis Alpha'), true);
      expect(updates.targetId, 'A');
      await tester.runAsync(() async {
        h.devices['A']!.drop();
        updates.invalidate();
        await shared.until(() => updates.transfer.awaitingReconnect);
        await h.connect('B');
        updates.bind(h.session.currentConnection!, h.repo);
      });
      service.connected = true;
      service.scooterName = 'Current Beta';
      store.scooters['A'] = SavedScooter(id: 'A', name: 'Renamed Alpha', color: 1);
      await tester.pumpWidget(_screen(service, locale));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect to Unustasis Alpha to confirm the installation before starting another update.'), findsOneWidget);
      expect(find.text('ls_ota_awaiting_confirmation'), findsNothing);
      expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged, isNull);
      final beta = h.repo;
      await tester.runAsync(() async {
        updates.sessionReady();
        await updates.refresh();
        await updates.executeStep(shared.stepFor(shared.release('v2.0.0')));
      });
      expect(beta.control.writes, isEmpty);
      expect(beta.data.writes, isEmpty);
      expect(updates.targetId, 'A');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_screen(service, locale));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reconnect to Unustasis Alpha'), findsOneWidget);
      await tester.runAsync(() async {
        updates.invalidate();
        await h.connect('A');
        updates.bind(h.session.currentConnection!, h.repo);
        h.repo.probePhase = 4;
        updates.sessionReady();
        await shared.until(() => updates.transfer.state == OtaTransferState.success);
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Reconnect to Unustasis Alpha'), findsNothing);
      expect(service.updateTargetName, 'Unustasis Alpha');
      expect(updates.transfer.state, OtaTransferState.success);
      expect(h.repo.control.writes.map((v) => v.first), [5]); // STATUS_REQ only.
      expect(h.repo.data.writes, isEmpty);
      expect(beta.control.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      await tester.runAsync(h.close);
    });
  }
}
