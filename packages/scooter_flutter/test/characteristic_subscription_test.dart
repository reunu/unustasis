import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/scooter_flutter.dart';

class _Characteristic implements BluetoothCharacteristic {
  final values = StreamController<List<int>>.broadcast(sync: true);
  bool failNotify = false;
  bool failRead = false;
  bool? notificationRequest;
  bool readHadListener = false;

  @override
  Stream<List<int>> get lastValueStream => values.stream;

  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    notificationRequest = notify;
    if (failNotify) throw StateError('disconnected during notification setup');
    return true;
  }

  @override
  Future<List<int>> read({int timeout = 15}) async {
    readHadListener = values.hasListener;
    if (failRead) throw StateError('disconnected during initial read');
    values.add([42]);
    return [42];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('subscribes before initial read and forwards subsequent values', () async {
    final characteristic = _Characteristic();
    addTearDown(characteristic.values.close);
    final received = <List<int>>[];
    final subscription = subscribeCharacteristic(characteristic, received.add);
    addTearDown(subscription.cancel);

    expect(characteristic.notificationRequest, isTrue);
    expect(characteristic.readHadListener, isTrue);
    characteristic.values.add([43]);
    expect(received, [[42], [43]]);

    await subscription.cancel();
    expect(characteristic.values.hasListener, isFalse);
    characteristic.values.add([44]);
    expect(received, [[42], [43]]);
  });

  test('async setup failures do not become unhandled errors', () async {
    final characteristic = _Characteristic()
      ..failNotify = true
      ..failRead = true;
    addTearDown(characteristic.values.close);
    final received = <List<int>>[];
    final subscription = subscribeCharacteristic(characteristic, received.add);
    addTearDown(subscription.cancel);

    // Drain futures from both failed setup calls; the test zone catches any
    // uncaught asynchronous error automatically.
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    characteristic.values.add([7]);
    expect(received, [[7]]);
  });
}
