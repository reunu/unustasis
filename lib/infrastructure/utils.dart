import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

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
  characteristic.setNotifyValue(true);
  final StreamSubscription<List<int>> subscription = characteristic.lastValueStream.listen(onData);
  characteristic.read();
  return subscription;
}

extension DateTimeExtension on DateTime {
  String calculateExactTimeDifferenceInShort(BuildContext context) {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '${(difference.inDays / 7).floor()}W';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}D';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}H';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}M';
    } else {
      return FlutterI18n.translate(context, "stats_last_ping_now");
    }
  }
}
