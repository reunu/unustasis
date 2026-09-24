import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import '../support/persistence_fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/scooter_storage.dart';
import '../../packages/scooter_flutter/test/navigation_runtime_test.dart' as transport;
import '../../packages/scooter_flutter/test/update_controller_test.dart' as shared;

class _Storage extends Fake implements ScooterStorage {
  @override
  Map<String, SavedScooter> scooters = {
    'A': SavedScooter(id: 'A', name: 'Captured Alpha', color: 1),
    'B': SavedScooter(id: 'B', name: 'Previous Beta', color: 2),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferencesAsyncPlatform.instance = MemoryPreferences());
  for (final phase in [0, 1, 2, 3]) {
    test('actual app composition captures fresh STATUS phase $phase name before state publication', () async {
      final h = shared.UpdateHarness();
      await h.init();
      final store = _Storage();
      // Exercise the real facade's display-name composition with an explicitly
      // bound fake session token. No facade startup, transport or HTTP is run.
      final service = ScooterService(transport.Bluetooth(), storage: store, initializeRuntime: false);
      final updates = service.updateController;
      updates.targetId = 'B';
      updates.onTargetCaptured!('B');
      updates.transfer.state = OtaTransferState.success;
      updates.transfer.notifyListeners();
      expect(service.updateTargetName, 'Previous Beta');
      updates.transfer.reset();
      updates.bind(h.session.currentConnection!, h.repo);
      h.repo.probePhase = phase;
      final namesAtPublication = <String?>[];
      updates.transfer.addListener(() {
        namesAtPublication.add(service.updateTargetName);
        // A later record rename must not relabel the already captured install.
        store.scooters['A'] = SavedScooter(id: 'A', name: 'Renamed later', color: 1);
      });
      try {
        await updates.refresh();
        expect(namesAtPublication, isNotEmpty);
        expect(namesAtPublication.every((name) => name == 'Captured Alpha'), true);
        expect(updates.targetId, 'A');
        if (phase != 2) {
          h.devices['A']!.drop();
          updates.invalidate();
          await shared.until(() => updates.transfer.awaitingReconnect);
          await h.connect('B');
          updates.bind(h.session.currentConnection!, h.repo);
          h.repo.probePhase = 4;
          await updates.refresh();
          expect(h.repo.control.writes, isEmpty);
          expect(service.updateTargetName, 'Captured Alpha');
          await h.connect('A');
          updates.bind(h.session.currentConnection!, h.repo);
          h.repo.probePhase = 4;
          await updates.refresh();
          expect(updates.transfer.state, OtaTransferState.success);
          expect(service.updateTargetName, 'Captured Alpha');
        }
      } finally {
        service.dispose();
        await h.close();
      }
    });
  }
  test('fresh STATUS name falls back to captured ID, never previous target name', () async {
    final h = shared.UpdateHarness();
    await h.init();
    final store = _Storage()..scooters.remove('A');
    final service = ScooterService(transport.Bluetooth(), storage: store, initializeRuntime: false);
    final updates = service.updateController;
    updates.targetId = 'B';
    updates.onTargetCaptured!('B');
    updates.transfer.notifyListeners();
    updates.bind(h.session.currentConnection!, h.repo);
    h.repo.probePhase = 2;
    try {
      await updates.refresh();
      expect(service.updateTargetName, 'A');
      expect(updates.targetId, 'A');
    } finally {
      service.dispose();
      await h.close();
    }
  });
  test('fresh same-ID adoption recaptures renamed A but recovery keeps that capture', () async {
    final h = shared.UpdateHarness();
    await h.init();
    final store = _Storage();
    final service = ScooterService(transport.Bluetooth(), storage: store, initializeRuntime: false);
    final updates = service.updateController;
    updates.bind(h.session.currentConnection!, h.repo);
    h.repo.probePhase = 1;
    try {
      await updates.refresh();
      h.repo.status.values.add([0x84, 4, 100, 0]);
      await shared.until(() => updates.transfer.state == OtaTransferState.success);
      expect(service.updateTargetName, 'Captured Alpha');
      store.scooters['A'] = SavedScooter(id: 'A', name: 'Fresh Alpha', color: 1);
      updates.transfer.reset();
      await updates.refresh();
      expect(service.updateTargetName, 'Fresh Alpha');
      store.scooters['A'] = SavedScooter(id: 'A', name: 'Later Alpha', color: 1);
      h.devices['A']!.drop();
      updates.invalidate();
      await shared.until(() => updates.transfer.awaitingReconnect);
      await h.connect('A');
      updates.bind(h.session.currentConnection!, h.repo);
      h.repo.probePhase = 4;
      await updates.refresh();
      expect(updates.transfer.state, OtaTransferState.success);
      expect(service.updateTargetName, 'Fresh Alpha');
    } finally {
      service.dispose();
      await h.close();
    }
  });
}
