import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

class TransportTestDevice extends Fake implements BluetoothDevice {
  @override
  bool isDisconnected = false;
}

class TransportTestWrite {
  TransportTestWrite(List<int> bytes, this.allowLongWrite, this.withoutResponse) : bytes = List.of(bytes);
  final List<int> bytes;
  final bool allowLongWrite;
  final bool withoutResponse;
  String get command => ascii.decode(bytes);
}

class TransportTestCharacteristic extends Fake implements BluetoothCharacteristic {
  final writes = <TransportTestWrite>[];
  final notifyCalls = <bool>[];
  final values = StreamController<List<int>>.broadcast(sync: true);
  Future<void> Function(TransportTestWrite)? onWrite;
  Completer<void>? notifyGate;
  int listeners = 0;
  int maxListeners = 0;
  int cancellations = 0;

  @override
  bool isNotifying = false;

  @override
  Stream<List<int>> get onValueReceived => Stream<List<int>>.multi((sink) {
        listeners++;
        if (listeners > maxListeners) maxListeners = listeners;
        final subscription = values.stream.listen(
          sink.addSync,
          onError: sink.addErrorSync,
          onDone: sink.closeSync,
        );
        sink.onCancel = () {
          listeners--;
          cancellations++;
          return subscription.cancel();
        };
      }, isBroadcast: true);

  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) async {
    notifyCalls.add(notify);
    if (notifyGate != null) await notifyGate!.future;
    isNotifying = notify;
    return true;
  }

  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    final write = TransportTestWrite(value, allowLongWrite, withoutResponse);
    writes.add(write);
    await onWrite?.call(write);
  }

  void reply(String response) => values.add(utf8.encode(response));
}
