import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'update_controller_test.dart';

void main() {
  late UpdateHarness h;
  var controllerDisposed = false;
  setUp(() async {
    controllerDisposed = false;
    h = UpdateHarness();
    await h.init();
  });
  tearDown(() => h.close(disposeController: !controllerDisposed));

  test('cold STATUS adoption owns A before publication and recovers on fresh A',
      () async {
    final publishedTargets = <String?>[];
    h.controller.transfer.addListener(() {
      if (h.controller.transfer.state == OtaTransferState.installing) {
        publishedTargets.add(h.controller.targetId);
      }
    });
    h.repo.probePhase = 1;
    await h.controller.refresh();
    h.devices['A']!.drop();
    await until(() => h.controller.transfer.awaitingReconnect);
    await h.connect('A');
    h.repo.probePhase = 4;
    await h.controller.refresh();
    expect(publishedTargets, isNotEmpty);
    expect(publishedTargets.every((id) => id == 'A'), true);
    expect(h.repo.control.writes, [
      [5]
    ]);
    expect(h.controller.transfer.state, OtaTransferState.success);
    expect(h.controller.targetId, 'A');
    expect(h.repo.data.writes, isEmpty);
  });

  test('previous completed B cannot own or confirm newly adopted A', () async {
    await h.connect('B');
    await h.controller.executeStep(stepFor(release('v2.0.0')));
    expect(h.controller.targetId, 'B');
    h.controller.transfer.reset();
    await h.connect('A');
    h.repo.probePhase = 1;
    await h.controller.refresh();
    h.devices['A']!.drop();
    await until(() => h.controller.transfer.awaitingReconnect);
    await h.connect('B');
    h.repo.probePhase = 4;
    await h.controller.refresh();
    expect(h.repo.control.writes, isEmpty);
    expect(h.controller.targetId, 'A');
    expect(h.controller.transfer.awaitingReconnect, true);
  });

  for (final phase in ['query', 'index']) {
    for (final id in ['A', 'B']) {
      for (final readyBeforeFinally in [true, false]) {
        test(
            'interrupted $phase recovers once on $id ready ${readyBeforeFinally ? "before" : "after"} old finally',
            () async {
          final queryGate = Completer<void>();
          final indexGate = Completer<List<FirmwareRelease>>();
          final old = h.repo;
          if (phase == 'query') {
            old.wire.onWrite = (command) async {
              await queryGate.future;
              old.wire.reply('$command:v1.0.0');
            };
          } else {
            h.provider.indexGate = indexGate;
          }
          final run = h.controller.refresh();
          await until(() => phase == 'query'
              ? h.trace.contains('A:status:version:mdb')
              : h.provider.channels.isNotEmpty);
          h.autoReady = true;
          h.devices['A']!.drop();
          if (readyBeforeFinally) await h.connect(id);
          h.provider.indexGate = null;
          if (phase == 'query') {
            queryGate.complete();
          } else {
            indexGate.complete([release('v9.0.0')]);
          }
          await run;
          if (!readyBeforeFinally) await h.connect(id);
          await until(() => h.controller.plan != null);
          expect(h.controller.phase, UpdatePlanPhase.ready);
          expect(h.controller.plan!.steps.first.release.tagName, 'v2.0.0');
          expect(h.provider.channels.length, phase == 'query' ? 1 : 2);
          h.controller.sessionReady();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(h.provider.channels.length, phase == 'query' ? 1 : 2);
          expect(h.provider.urls, isEmpty);
          expect(h.repo.data.writes, isEmpty);
        });
      }
    }
  }
  for (final priorB in [false, true]) {
    test(
        'adopted state publication owns A across reentrant B replacement (prior B=$priorB)',
        () async {
      if (priorB) {
        await h.connect('B');
        await h.controller.executeStep(stepFor(release('v2.0.0')));
        h.controller.transfer.reset();
        await h.connect('A');
      }
      h.repo.probePhase = 1;
      Future<void>? replacement;
      String? publishedTarget;
      h.controller.transfer.addListener(() {
        if (replacement == null &&
            h.controller.transfer.state == OtaTransferState.installing) {
          publishedTarget = h.controller.targetId;
          replacement = h.connect('B');
        }
      });
      await h.controller.refresh();
      await replacement;
      expect(publishedTarget, 'A');
      expect(h.controller.targetId, 'A');
      expect(h.controller.transfer.awaitingReconnect, true);
      h.repo.probePhase = 4;
      await h.controller.refresh();
      expect(h.repo.control.writes, isEmpty);
      expect(
          h.allRepos
              .where((r) => r != h.repo)
              .every((r) => !r.status.values.hasListener),
          true);
    });
  }

  test(
      'reentrant owner capture replacement cannot publish obsolete adopted state',
      () async {
    h.repo.probePhase = 1;
    final original = h.repo;
    Future<void>? replacement;
    final states = <OtaTransferState>[];
    h.controller.transfer
        .addListener(() => states.add(h.controller.transfer.state));
    h.controller.addListener(() {
      if (h.controller.targetId == 'A' && replacement == null) {
        replacement = h.connect('B');
      }
    });
    await h.controller.refresh();
    await replacement;
    expect(states, isEmpty);
    expect(original.status.values.hasListener, false);
    expect(h.controller.transfer.state, OtaTransferState.idle);
    expect(h.repo.control.writes, isEmpty);
  });

  test(
      'recovery keeps A when a stale same-ID STATUS result finishes after B replacement',
      () async {
    h.repo.probePhase = 1;
    await h.controller.refresh();
    h.devices['A']!.drop();
    await until(() => h.controller.transfer.awaitingReconnect);
    await h.connect('A');
    final gate = Completer<void>();
    final recovering = h.repo;
    recovering.control.onWrite = (_) async {
      await gate.future;
      recovering.status.values.add([0x84, 4, 100, 0]);
    };
    final run = h.controller.refresh();
    await until(() => recovering.control.writes.isNotEmpty);
    await h.connect('B');
    gate.complete();
    await run;
    await h.controller.refresh();
    expect(h.controller.targetId, 'A');
    expect(h.controller.transfer.awaitingReconnect, true);
    expect(h.controller.transfer.state, OtaTransferState.installing);
    expect(h.repo.control.writes, isEmpty);
    expect(recovering.status.values.hasListener, false);
  });

  test('interrupted channel switch preserves the explicit choice on recovery',
      () async {
    final gate = Completer<List<FirmwareRelease>>();
    h.provider.indexGate = gate;
    final run =
        h.controller.refresh(selectedChannel: 'testing', channelSwitch: true);
    await until(() => h.provider.channels.isNotEmpty);
    h.devices['A']!.drop();
    h.autoReady = true;
    await h.connect('B');
    h.provider.indexGate = null;
    h.provider.releases = [release('testing-20260102T000000')];
    gate.complete([release('testing-20260101T000000')]);
    await run;
    await until(() => h.controller.plan != null);
    expect(h.provider.channels, ['testing', 'testing']);
    expect(h.controller.channelSwitch, true);
    expect(h.controller.plan!.steps.first.kind, StepKind.channelSwitchFull);
  });

  test('reentrant newer channel choice supersedes queued interrupted planning',
      () async {
    final gate = Completer<List<FirmwareRelease>>();
    h.provider.indexGate = gate;
    final run = h.controller.refresh();
    await until(() => h.provider.channels.isNotEmpty);
    h.devices['A']!.drop();
    h.autoReady = true;
    await h.connect('B');
    var selected = false;
    h.controller.addListener(() {
      if (!selected &&
          !h.controller.busy &&
          h.controller.phase == UpdatePlanPhase.idle) {
        selected = true;
        unawaited(h.controller
            .refresh(selectedChannel: 'testing', channelSwitch: true));
      }
    });
    h.provider.indexGate = null;
    h.provider.releases = [release('testing-20260102T000000')];
    gate.complete([release('v9.0.0')]);
    await run;
    await until(() => h.controller.plan != null);
    expect(selected, true);
    expect(h.provider.channels, ['stable', 'testing']);
    h.controller.sessionReady();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.provider.channels, ['stable', 'testing']);
  });

  for (final outcome in ['plan', 'error']) {
    test(
        'newer explicit $outcome supersedes interrupted planning and readiness does not retry',
        () async {
      final gate = Completer<List<FirmwareRelease>>();
      h.provider.indexGate = gate;
      final run = h.controller.refresh();
      await until(() => h.provider.channels.isNotEmpty);
      h.devices['A']!.drop();
      h.provider.indexGate = null;
      gate.complete([release('v9.0.0')]);
      await run;
      await h.connect(
          'B'); // Ready delivery is held until the explicit check settles.
      if (outcome == 'error') {
        h.provider.indexError = const UpdateHttpError(503, index: true);
      }
      await h.controller.refresh();
      final plan = h.controller.plan;
      final error = h.controller.error;
      h.controller.sessionReady();
      h.controller.sessionReady();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.provider.channels.length, 2);
      expect(h.controller.plan, same(plan));
      expect(h.controller.error, same(error));
      expect(h.controller.phase,
          outcome == 'plan' ? UpdatePlanPhase.ready : UpdatePlanPhase.error);
    });
  }

  test('failed recovered index remains error until explicit retry, never loops',
      () async {
    final gate = Completer<List<FirmwareRelease>>();
    h.provider.indexGate = gate;
    final run = h.controller.refresh();
    await until(() => h.provider.channels.isNotEmpty);
    h.devices['A']!.drop();
    h.autoReady = true;
    await h.connect('B');
    h.provider.indexGate = null;
    h.provider.indexError = const UpdateHttpError(503, index: true);
    gate.complete([release('v9.0.0')]);
    await run;
    await until(() => h.controller.phase == UpdatePlanPhase.error);
    h.controller.sessionReady();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.provider.channels.length, 2);
    h.provider.indexError = null;
    await h.controller.refresh();
    expect(h.provider.channels.length, 3);
    expect(h.controller.phase, UpdatePlanPhase.ready);
  });

  test(
      'obsolete readiness cannot refresh a replacement binding before it is ready',
      () async {
    final gate = Completer<List<FirmwareRelease>>();
    h.provider.indexGate = gate;
    final run = h.controller.refresh();
    await until(() => h.provider.channels.isNotEmpty);
    h.devices['A']!.drop();
    h.autoReady = true;
    await h.connect('B');
    h.devices['B']!.drop();
    h.autoReady = false;
    await h.connect('A');
    h.provider.indexGate = null;
    gate.complete([release('v9.0.0')]);
    await run;
    expect(h.controller.plan, null);
    expect(h.provider.channels.length, 1);
    h.controller.sessionReady();
    await until(() => h.controller.plan != null);
    expect(h.provider.channels.length, 2);
  });

  for (final operation in ['adoption', 'execute']) {
    for (final transition in ['B', 'same-ID', 'disconnect', 'dispose']) {
      test(
          '$operation target-capture effect rejects reentrant $transition before state or writes',
          () async {
        await h.close();
        Future<void>? replacement;
        h = UpdateHarness(onTargetCaptured: (id) {
          expect(id, 'A');
          if (transition == 'dispose') {
            controllerDisposed = true;
            h.controller.dispose();
          } else if (transition == 'disconnect') {
            h.devices['A']!.drop();
          } else {
            if (transition == 'same-ID') h.devices['A']!.drop();
            replacement = h.connect(transition == 'same-ID' ? 'A' : 'B');
          }
        });
        await h.init();
        h.repo.probePhase = 1;
        final original = h.repo;
        final states = <OtaTransferState>[];
        h.controller.transfer
            .addListener(() => states.add(h.controller.transfer.state));
        if (operation == 'adoption') {
          await h.controller.refresh();
        } else {
          await h.controller.executeStep(stepFor(release('v2.0.0')));
        }
        await replacement;
        expect(states, isEmpty);
        expect(
            original.control.writes,
            operation == 'adoption'
                ? [
                    [5]
                  ]
                : isEmpty);
        expect(original.status.values.hasListener, false);
        expect(h.controller.transfer.activeStep, null);
        expect(h.controller.busy, false);
        expect(h.provider.urls, isEmpty);
      });
    }
  }
}
