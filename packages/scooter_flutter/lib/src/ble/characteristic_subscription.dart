import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

final _log = Logger('ScooterCharacteristics');

/// Subscribes to a characteristic's values and hands back the subscription.
///
/// Cancel it when the connection goes away. lastValueStream is derived from a
/// global platform stream that never closes, so a listener left behind
/// outlives the disconnect and every reconnect stacks another copy of the
/// handler on top of it.
StreamSubscription<List<int>> subscribeCharacteristic(
  BluetoothCharacteristic characteristic,
  Function(List<int>) onData,
) {
  // The device can drop while this setup is in flight; without the guards
  // every failed notification setup surfaces as an unhandled async error.
  characteristic.setNotifyValue(true).catchError((Object e) {
    _log.warning('Failed to enable notifications: $e');
    return false;
  });
  final StreamSubscription<List<int>> subscription = characteristic.lastValueStream.listen(onData);
  characteristic.read().catchError((Object e) {
    _log.warning('Failed to read characteristic after subscribing: $e');
    return <int>[];
  });
  return subscription;
}
