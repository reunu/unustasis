import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/alarm_wake_sources.dart';
import 'package:scooter_core/scooter_battery.dart';
import 'package:scooter_flutter/src/ble/scooter_reader.dart';

class _Characteristic implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  List<int> readValue = [];
  bool failRead = false;
  int reads = 0;
  final notificationRequests = <bool>[];

  @override
  Stream<List<int>> get lastValueStream => values.stream;

  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    notificationRequests.add(notify);
    return true;
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    reads++;
    if (failRead) throw StateError('read failed');
    // Match the plugin: a successful read also emits on lastValueStream.
    values.add(readValue);
    return readValue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _Characteristic characteristic;

  setUp(() {
    characteristic = _Characteristic();
    addTearDown(characteristic.values.close);
  });

  group('subscriptions', () {
    test('string initial read and updates decode UTF-8, NULs and whitespace',
        () {
      characteristic.readValue = utf8.encode(' \tGrüße\u0000 🛵\n');
      final received = <String>[];
      final subscription =
          subscribeToStringValue(characteristic, 'test', received.add);
      addTearDown(subscription.cancel);

      characteristic.values.add([65, 0, 66, 32, 67]);
      characteristic.values.add([0xff]);
      characteristic.values.add([]);
      expect(received, ['Grüße 🛵', 'AB C', '\uFFFD', '']);
      expect(characteristic.notificationRequests, [true]);
      expect(characteristic.reads, 1);
    });

    test('uint32 filters wrong lengths and preserves unsigned values', () {
      characteristic.readValue = [0x78, 0x56, 0x34, 0x12];
      final received = <int>[];
      final subscription =
          subscribeToIntValue(characteristic, 'test', received.add);
      addTearDown(subscription.cancel);

      for (final length in [0, 1, 2, 3, 5, 8]) {
        characteristic.values.add(List.filled(length, 0));
      }
      characteristic.values.add([0, 0, 0, 0x80]);
      characteristic.values.add([255, 255, 255, 255]);
      expect(received, [0x12345678, 2147483648, 4294967295]);
    });

    test('single-byte integer takes first byte and ignores empty values',
        () async {
      characteristic.readValue = [255];
      final received = <int>[];
      final subscription = subscribeToIntValue(
        characteristic,
        'test',
        received.add,
        singleByte: true,
      );
      addTearDown(subscription.cancel);
      characteristic.values.add([]);
      characteristic.values.add([0]);
      characteristic.values.add([7, 8, 9, 10, 11]);
      expect(received, [255, 0, 7]);

      await subscription.cancel();
      characteristic.values.add([42]);
      expect(received, [255, 0, 7]);
    });

    test('alarm filters malformed lengths and forwards parsed fields', () {
      final received = <AlarmWakeSources>[];
      final subscription =
          subscribeToAlarmWakeSources(characteristic, received.add);
      addTearDown(subscription.cancel);
      for (final length in [0, 1, 2, 3, 4, 5, 7, 8]) {
        characteristic.values.add(List.filled(length, 0));
      }
      expect(received, isEmpty);
      characteristic.values.add([1, 0x1f, 0x02, 0x01, 0, 0]);
      characteristic.values.add([0, 0, 0, 0, 0, 0]);
      expect(received, hasLength(2));
      final sources = received.first;
      expect(sources.hibernating, isTrue);
      expect(sources.motionWouldWake, isTrue);
      expect(sources.wakeTimerArmed, isTrue);
      expect(sources.brakeWouldWake, isTrue);
      expect(sources.bleWouldWake, isTrue);
      expect(sources.lowCbbWouldWake, isTrue);
      expect(sources.wakeTimerDuration, const Duration(seconds: 258));
      expect(received.last.hibernating, isFalse);
      expect(received.last.wakeTimerDuration, isNull);
    });

    test('CBB forwards known states only after string normalization', () {
      final received = <bool>[];
      final subscription = subscribeToCbbCharging(characteristic, received.add);
      addTearDown(subscription.cancel);
      for (final value in [
        ' charging\u0000 ',
        'not-charging',
        'unknown',
        'Charging',
        '',
        'charging'
      ]) {
        characteristic.values.add(utf8.encode(value));
      }
      expect(received, [true, false, true]);
    });

    test('AUX forwards each known state and ignores unknown states', () {
      final received = <AUXChargingState>[];
      final subscription = subscribeToAuxCharging(characteristic, received.add);
      addTearDown(subscription.cancel);
      for (final value in [
        ' float-charge\u0000 ',
        'absorption-charge',
        'bulk-charge',
        'not-charging',
        'charging',
        'FLOAT-CHARGE',
        ''
      ]) {
        characteristic.values.add(utf8.encode(value));
      }
      expect(received, [
        AUXChargingState.floatCharge,
        AUXChargingState.absorptionCharge,
        AUXChargingState.bulkCharge,
        AUXChargingState.none,
      ]);
    });
  });

  group('readOdometer', () {
    test('calls back once with unsigned metres and accepts padding', () async {
      characteristic.readValue = [255, 255, 255, 255, 99];
      final received = <int>[];
      await readOdometer(characteristic, received.add);
      characteristic.values.add([1, 0, 0, 0]);
      expect(received, [4294967295]);
      expect(characteristic.reads, 1);
      expect(characteristic.notificationRequests, isEmpty);
      expect(characteristic.values.hasListener, isFalse);
    });

    test('accepts an exact four-byte zero value', () async {
      characteristic.readValue = [0, 0, 0, 0];
      final received = <int>[];
      await readOdometer(characteristic, received.add);
      expect(received, [0]);
    });

    test('does not call back for any truncated payload', () async {
      final received = <int>[];
      for (var length = 0; length < 4; length++) {
        characteristic.readValue = List.filled(length, 0);
        await readOdometer(characteristic, received.add);
      }
      expect(received, isEmpty);
    });

    test('read errors complete normally without calling back', () async {
      characteristic.failRead = true;
      final received = <int>[];
      await readOdometer(characteristic, received.add);
      expect(received, isEmpty);
      expect(characteristic.reads, 1);
    });

    test('callback errors are swallowed without retrying the callback',
        () async {
      characteristic.readValue = [1, 0, 0, 0];
      var calls = 0;
      await readOdometer(characteristic, (_) {
        calls++;
        throw StateError('consumer failed');
      });
      expect(calls, 1);
    });
  });

  group('readNrfVersion', () {
    test('normalizes version and identifies the case-sensitive -ls substring',
        () async {
      final received = <(String, bool)>[];
      for (final version in [
        ' \t1.2.3-ls\u0000\n',
        '1.2.3',
        '1-ls-preview',
        '1-LS'
      ]) {
        characteristic.readValue = utf8.encode(version);
        await readNrfVersion(
            characteristic, (value, ls) => received.add((value, ls)));
      }
      expect(received, [
        ('1.2.3-ls', true),
        ('1.2.3', false),
        ('1-ls-preview', true),
        ('1-LS', false)
      ]);
      expect(characteristic.reads, 4);
      expect(characteristic.notificationRequests, isEmpty);
      expect(characteristic.values.hasListener, isFalse);
      characteristic.values.add(utf8.encode('later-ls'));
      expect(received, hasLength(4));
    });

    test('malformed UTF-8 and empty payload still invoke the callback',
        () async {
      final received = <(String, bool)>[];
      for (final bytes in <List<int>>[
        [0xff, 45, 108, 115],
        [],
        [0, 32, 0]
      ]) {
        characteristic.readValue = bytes;
        await readNrfVersion(
            characteristic, (value, ls) => received.add((value, ls)));
      }
      expect(received, [('\uFFFD-ls', true), ('', false), ('', false)]);
    });

    test('read errors complete normally without calling back', () async {
      characteristic.failRead = true;
      var calls = 0;
      await readNrfVersion(characteristic, (_, __) => calls++);
      expect(calls, 0);
      expect(characteristic.reads, 1);
    });

    test('callback errors are swallowed without retrying the callback',
        () async {
      characteristic.readValue = utf8.encode('1.0-ls');
      var calls = 0;
      await readNrfVersion(characteristic, (_, __) {
        calls++;
        throw StateError('consumer failed');
      });
      expect(calls, 1);
    });
  });
}
