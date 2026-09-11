import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

import 'telemetry_stale_reproduction_test.dart' show LateStream;

class _Characteristic extends Fake implements BluetoothCharacteristic {
  final received = LateStream();
  final notifications = <Completer<bool>>[];
  final reads = <Completer<List<int>>>[];
  int cacheListens = 0;

  @override
  Stream<List<int>> get lastValueStream {
    cacheListens++;
    return Stream.value('locked'.codeUnits);
  }

  @override
  Stream<List<int>> get onValueReceived => received;

  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) {
    final gate = Completer<bool>();
    notifications.add(gate);
    return gate.future;
  }

  @override
  Future<List<int>> read({int timeout = 15}) {
    final gate = Completer<List<int>>();
    reads.add(gate);
    return gate.future;
  }

  void text(String value) => received.deliver(value.codeUnits);
}

class _Harness {
  final status = VehicleStatus();
  final handlebar = _Characteristic();
  final alarm = _Characteristic();
  final trigger = _Characteristic();
  final wake = _Characteristic();
  final ordinary = _Characteristic();
  int publications = 0;

  List<_Characteristic> get protection => [handlebar, alarm, trigger, wake];

  void wire({bool optional = true, bool Function()? isCurrent}) {
    final repo = CharacteristicRepository(BluetoothDevice.fromId('A'))
      ..stateCharacteristic = ordinary
      ..powerStateCharacteristic = null
      ..umsStatusCharacteristic = null
      ..navigationActiveCharacteristic = null
      ..seatCharacteristic = ordinary
      ..handlebarCharacteristic = handlebar
      ..alarmStatusCharacteristic = optional ? alarm : null
      ..alarmLastTriggerCharacteristic = optional ? trigger : null
      ..alarmWakeSourcesCharacteristic = optional ? wake : null;
    status.wireSubscriptions(repo,
        isCurrent: isCurrent,
        onStateUpdate: () {},
        onSeatUpdate: () {},
        onNavigationChanged: () {},
        onUsbModeChanged: () {},
        onHandlebarsChanged: (_) => publications++,
        onAlarmChanged: () => publications++);
  }

  void populate() {
    handlebar.text('locked');
    alarm.text('armed');
    trigger.text('motion,2026-01-02T03:04:05Z');
    wake.received.deliver([1, 3, 60, 0, 0, 0]);
    expect(status.handlebarsLocked, true);
    expect(status.alarmStatus, AlarmStatus.armed);
    expect(status.alarmLastTrigger, isNotNull);
    expect(status.alarmWakeSources, isNotNull);
  }

  void expectUnknown() {
    expect(status.handlebarsLocked, isNull);
    expect(status.alarmStatus, isNull);
    expect(status.alarmLastTrigger, isNull);
    expect(status.alarmWakeSources, isNull);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('production VehicleStatus only maps decoded locked/unlocked to booleans',
      () async {
    final h = _Harness()..wire();
    addTearDown(h.status.cancelSubscriptions);
    await _flush();
    h.expectUnknown();
    expect(h.protection.map((c) => c.cacheListens), everyElement(0));
    for (final bytes in [
      <int>[],
      [0],
      'unknown'.codeUnits,
      'locking'.codeUnits,
      'LOCKED'.codeUnits,
      [255],
      'not-unlocked'.codeUnits,
    ]) {
      h.handlebar.text('locked');
      h.handlebar.received.deliver(bytes);
      expect(h.status.handlebarsLocked, isNull, reason: '$bytes');
    }
    h.handlebar.received.deliver([0, ...' locked '.codeUnits, 0]);
    expect(h.status.handlebarsLocked, true);
    h.handlebar.text('unlocked');
    expect(h.status.handlebarsLocked, false);
  });

  for (final replacement in ['cancel', 'same source', 'missing alarm']) {
    test('$replacement clears all protection and rejects queued old callbacks',
        () async {
      final h = _Harness()..wire();
      addTearDown(h.status.cancelSubscriptions);
      h.populate();
      final oldCallbacks =
          h.protection.map((c) => c.received.callbacks.single).toList();
      if (replacement == 'cancel') {
        h.status.cancelSubscriptions();
      } else {
        h.wire(optional: replacement != 'missing alarm');
      }
      h.expectUnknown();
      final count = h.publications;
      for (final callback in oldCallbacks) {
        callback('locked'.codeUnits);
        callback('armed'.codeUnits);
        callback('motion,2026-01-02T03:04:05Z'.codeUnits);
        callback([1, 3, 60, 0, 0, 0]);
      }
      for (final c in h.protection) {
        c.notifications.first.complete(true);
      }
      await _flush();
      expect(h.protection.map((c) => c.reads.length), everyElement(0));
      expect(h.publications, count);
      h.expectUnknown();
      if (replacement != 'cancel') {
        h.handlebar.notifications.last.complete(true);
        await _flush();
        expect(h.handlebar.reads.length, 1);
        h.handlebar.text('unlocked');
        expect(h.status.handlebarsLocked, false);
      }
    });
  }

  test('external application ownership stops setup and events', () async {
    var current = true;
    final h = _Harness()..wire(isCurrent: () => current);
    addTearDown(h.status.cancelSubscriptions);
    current = false;
    for (final c in h.protection) {
      c.notifications.single.complete(true);
      c.text('locked');
    }
    await _flush();
    expect(h.protection.map((c) => c.reads.length), everyElement(0));
    expect(h.publications, 0);
    h.expectUnknown();
  });

  test('obsolete read Future is ignored without waiting for native drain',
      () async {
    final h = _Harness()..wire();
    addTearDown(h.status.cancelSubscriptions);
    h.handlebar.notifications.single.complete(true);
    await _flush();
    final oldRead = h.handlebar.reads.single;
    h.wire();
    h.handlebar.notifications.last.complete(true);
    await _flush();
    expect(h.handlebar.reads.length, 2);
    oldRead.complete('locked'.codeUnits);
    await _flush();
    h.expectUnknown();
    h.handlebar.text('unlocked');
    expect(h.status.handlebarsLocked, false);
    // This fake tests Future ownership only. Native same-identity events have
    // no such ownership; the real-FBP characterization covers that limitation.
  });

  for (final failure in ['notify', 'read']) {
    test('transient $failure failure does not quarantine a healthy reconnect',
        () async {
      final h = _Harness()..wire();
      addTearDown(h.status.cancelSubscriptions);
      if (failure == 'notify') {
        h.handlebar.notifications.single.completeError(StateError('transient'));
      } else {
        h.handlebar.notifications.single.complete(true);
        await _flush();
        h.handlebar.reads.single.completeError(TimeoutException('transient'));
      }
      await _flush();
      h.expectUnknown();
      h.wire();
      h.handlebar.notifications.last.complete(true);
      await _flush();
      expect(h.handlebar.reads.length, failure == 'read' ? 2 : 1);
      h.handlebar.text('locked');
      expect(h.status.handlebarsLocked, true);
      h.handlebar.reads.last.complete('locked'.codeUnits);
      await _flush();
    });
  }
}
