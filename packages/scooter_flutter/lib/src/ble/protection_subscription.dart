import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

final _log = Logger('ProtectionSubscription');

/// Protection is live-only: do not replay the plugin's last-value cache.
/// [isCurrent] owns application callbacks and setup continuations, not native
/// events. FBP cannot distinguish delayed same-identity native events from
/// current reads/notifications. Neither cancellation nor read completion drains
/// native operations; a later connection is free to try again after any error.
StreamSubscription<List<int>> subscribeProtectionCharacteristic(
  BluetoothCharacteristic characteristic,
  void Function(List<int>) onData, {
  required bool Function() isCurrent,
}) {
  final subscription = characteristic.onValueReceived.listen((data) {
    if (isCurrent()) onData(data);
  });
  Future<void> setup() async {
    try {
      if (!isCurrent()) return;
      await characteristic.setNotifyValue(true);
      if (!isCurrent()) return;
      // Values arrive through the non-replaying stream, never the Future.
      await characteristic.read();
    } catch (e, stack) {
      _log.warning('Failed to set up protection characteristic', e, stack);
    }
  }

  unawaited(setup());
  return subscription;
}
