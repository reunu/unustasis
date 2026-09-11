import 'dart:async';

import 'package:flutter/foundation.dart';

/// Waits for a value supplied by a [ChangeNotifier] without polling.
class StateWaiter<T> {
  StateWaiter({
    required ChangeNotifier notifier,
    required T Function() value,
    required this.expected,
    required this.timeout,
    required this.isDisconnected,
  }) : _notifier = notifier,
       _value = value;

  final ChangeNotifier _notifier;
  final T Function() _value;
  final T expected;
  final Duration timeout;
  final bool Function(T value) isDisconnected;
  void Function()? _cancel;

  Future<void> wait() {
    late final VoidCallback listener;
    Timer? timer;
    final completer = Completer<void>();

    void finish([Object? error, StackTrace? stackTrace]) {
      _cancel?.call();
      _cancel = null;
      if (completer.isCompleted) return;
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error, stackTrace);
      }
    }

    listener = () {
      final current = _value();
      if (current == expected) {
        finish();
      } else if (isDisconnected(current)) {
        finish(StateError('Scooter disconnected while waiting for $expected.'));
      }
    };

    _notifier.addListener(listener);
    _cancel = () {
      timer?.cancel();
      _notifier.removeListener(listener);
    };
    timer = Timer(timeout, () {
      finish(TimeoutException('Timed out waiting for $expected.', timeout));
    });
    return completer.future;
  }

  void cancel() {
    _cancel?.call();
    _cancel = null;
  }
}
