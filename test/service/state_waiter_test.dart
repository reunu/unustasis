import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/service/state_waiter.dart';

class _Notifier extends ChangeNotifier {
  String state = 'booting';
  int removals = 0;

  void update(String value) {
    state = value;
    notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    removals++;
    super.removeListener(listener);
  }
}

StateWaiter<String> _waiter(
  _Notifier notifier, {
  Duration timeout = const Duration(seconds: 1),
}) {
  return StateWaiter<String>(
    notifier: notifier,
    value: () => notifier.state,
    expected: 'standby',
    timeout: timeout,
    isDisconnected: (state) => state == 'disconnected',
  );
}

void main() {
  test('completes when a state notification reports standby', () async {
    final notifier = _Notifier();
    final future = _waiter(notifier).wait();

    notifier.update('standby');

    await expectLater(future, completes);
    expect(notifier.removals, 1);
  });

  test('reports a timeout and removes its listener', () async {
    final notifier = _Notifier();
    final future = _waiter(
      notifier,
      timeout: const Duration(milliseconds: 1),
    ).wait();

    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect(notifier.removals, 1);
  });

  test('reports disconnect notifications and removes its listener', () async {
    final notifier = _Notifier();
    final future = _waiter(notifier).wait();

    notifier.update('disconnected');

    await expectLater(future, throwsA(isA<StateError>()));
    expect(notifier.removals, 1);
  });
}
