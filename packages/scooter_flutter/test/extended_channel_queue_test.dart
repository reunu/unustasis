import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/command_transport.dart';

void main() {
  test('channel serializes work and preserves generic return values', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final first = withExtendedChannel(() async {
      events.add('first');
      entered.complete();
      await release.future;
      events.add('finished');
      return 42;
    });
    final second = withExtendedChannel(() async {
      events.add('second');
      return 'result';
    });
    await entered.future;
    expect(events, ['first']);
    release.complete();
    expect(await first, 42);
    expect(await second, 'result');
    expect(events, ['first', 'finished', 'second']);
  });

  test('a failed action does not poison the next queued action', () async {
    final error = StateError('write failed');
    final failed = withExtendedChannel<void>(() async => throw error);
    final checked = expectLater(failed, throwsA(same(error)));
    final next = withExtendedChannel(() async => 7);
    await checked;
    expect(await next, 7);
  });

  test('synchronous action throws are forwarded and queue recovers', () async {
    final error = StateError('before future');
    await expectLater(withExtendedChannel<void>(() => throw error), throwsA(same(error)));
    expect(await withExtendedChannel(() async => true), isTrue);
  });
}
