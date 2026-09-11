import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:scooter_flutter/command_transport.dart' show withExtendedChannel;
import 'package:unustasis/infrastructure/characteristic_repository.dart';
import 'package:unustasis/service/ble_commands.dart';

import '../support/command_transport_fakes.dart';

// Yield to queued microtasks without waiting for any protocol timeout.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

// Keep the real response listener's cancellation pending to exercise FIFO cleanup.
class _CleanupStream extends Stream<List<int>> {
  _CleanupStream(this.source, this.gate);
  final Stream<List<int>> source;
  final Completer<void> gate;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _CleanupSubscription(source.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError), gate);
}

class _CleanupSubscription extends Fake implements StreamSubscription<List<int>> {
  _CleanupSubscription(this.source, this.gate);
  final StreamSubscription<List<int>> source;
  final Completer<void> gate;

  @override
  Future<void> cancel() async {
    await gate.future;
    await source.cancel();
  }
}

class _CleanupCharacteristic extends TransportTestCharacteristic {
  final cleanup = Completer<void>();
  @override
  Stream<List<int>> get onValueReceived => _CleanupStream(super.onValueReceived, cleanup);
}

void main() {
  late TransportTestDevice device;
  late TransportTestCharacteristic basic;
  late TransportTestCharacteristic extended;
  late TransportTestCharacteristic response;
  late CharacteristicRepository repo;

  setUp(() {
    device = TransportTestDevice();
    basic = TransportTestCharacteristic();
    extended = TransportTestCharacteristic();
    response = TransportTestCharacteristic();
    repo = CharacteristicRepository(device)
      ..commandCharacteristic = basic
      ..extendedCommandCharacteristic = extended
      ..extendedResponseCharacteristic = response;
  });

  tearDown(() async {
    expect(response.listeners, 0, reason: 'Every response subscription is cancelled');
    await Future.wait([basic.values.close(), extended.values.close(), response.values.close()]);
  });

  test('root sendCommand writes ASCII with default flags', () async {
    await sendCommand(device, repo, 'scooter:state unlock');
    expect(basic.writes.single.bytes, ascii.encode('scooter:state unlock'));
    expect(basic.writes.single.allowLongWrite, isFalse);
    expect(basic.writes.single.withoutResponse, isFalse);
    expect(extended.writes, isEmpty);
  });

  test('custom characteristic and explicit long-write flag are preserved', () async {
    repo.commandCharacteristic = null;
    await sendCommand(device, repo, 'custom', characteristic: extended);
    await sendCommand(device, repo, 'x' * 100, characteristic: extended, allowLongWrite: true);
    expect(extended.writes.map((write) => write.command), ['custom', 'x' * 100]);
    expect(extended.writes.map((write) => write.allowLongWrite), [false, true]);
    expect(basic.writes, isEmpty);
  });

  test('non-ASCII commands fail before writing', () async {
    await expectLater(sendCommand(device, repo, 'café'), throwsA(isA<ArgumentError>()));
    expect(basic.writes, isEmpty);
  });

  test('basic command rejects missing scooter, disconnection and missing target', () async {
    await expectLater(sendCommand(null, repo, 'test'), throwsA('Scooter not found!'));
    device.isDisconnected = true;
    await expectLater(sendCommand(device, repo, 'test'), throwsA('Scooter disconnected!'));
    device.isDisconnected = false;
    repo.commandCharacteristic = null;
    await expectLater(sendCommand(device, repo, 'test'), throwsA('Could not send command, move closer or reconnect'));
    expect(basic.writes, isEmpty);
  });

  test('basic write failures propagate unchanged', () async {
    final error = StateError('write failed');
    basic.onWrite = (_) async => throw error;
    await expectLater(sendCommand(device, repo, 'test'), throwsA(same(error)));
  });

  test('extended validation rejects unavailable connections and characteristics', () async {
    await expectLater(sendLsExtendedCommand(null, repo, 'test'), throwsA('Scooter not connected!'));
    device.isDisconnected = true;
    await expectLater(sendLsExtendedCommand(device, repo, 'test'), throwsA('Scooter not connected!'));
    device.isDisconnected = false;
    repo.extendedCommandCharacteristic = null;
    await expectLater(
        sendLsExtendedCommand(device, repo, 'test'), throwsA('Extended command characteristics not available'));
    repo.extendedCommandCharacteristic = extended;
    repo.extendedResponseCharacteristic = null;
    await expectLater(
        sendLsExtendedCommand(device, repo, 'test'), throwsA('Extended command characteristics not available'));
    expect(response.notifyCalls, isEmpty);
    expect(extended.writes, isEmpty);
  });

  test('notification enable completes before listening and writing', () async {
    response.notifyGate = Completer<void>();
    extended.onWrite = (_) async {
      expect(response.isNotifying, isTrue);
      expect(response.listeners, 1);
      response.reply('ready');
    };
    final result = expectLater(sendLsExtendedCommand(device, repo, 'test'), completion('ready'));
    await _flush();
    expect(response.notifyCalls, [true]);
    expect(response.listeners, 0);
    expect(extended.writes, isEmpty);
    response.notifyGate!.complete();
    await result;
  });

  test('listens before write, buffers immediate replies and enables notify only once', () async {
    extended.onWrite = (write) async {
      expect(response.listeners, 1);
      response.reply('${write.command}:ok');
    };
    for (final command in ['first', 'second']) {
      await expectLater(sendLsExtendedCommand(device, repo, command), completion('$command:ok'));
      expect(response.listeners, 0);
    }
    expect(response.notifyCalls, [true]);
    expect(response.isNotifying, isTrue);
    expect(response.cancellations, 2);
    expect(extended.writes.every((write) => write.allowLongWrite), isTrue);
    expect(basic.writes, isEmpty);
  });

  test('lifecycle logs expose stages and byte counts but no command or response payload', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    });
    const command = 'fleet:pair super-secret-token remaining-payload';
    const reply = 'private-response-payload';
    extended.onWrite = (_) async => response.reply(reply);

    await expectLater(sendLsExtendedCommand(device, repo, command), completion(reply));

    final messages = records.where((record) => record.loggerName == 'BleCommands').map((record) => record.message);
    expect(messages, contains('Sending command (${ascii.encode(command).length} bytes)'));
    expect(messages, contains('Extended command received ${utf8.encode(reply).length} bytes'));
    expect(records.where((record) => record.loggerName == 'BleCommands').map((record) => record.level),
        containsAll([Level.FINE, Level.INFO]));
    for (final message in messages) {
      expect(message, isNot(contains('fleet')));
      expect(message, isNot(contains('pair')));
      expect(message, isNot(contains('super-secret-token')));
      expect(message, isNot(contains('private-response-payload')));
    }
  });

  test('timeout warning never derives a label from payload-like tokens', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    });
    const command = 'owner:keycard private-card-material';

    await expectLater(
      sendLsExtendedCommand(device, repo, command, responseTimeout: Duration.zero),
      completion(isNull),
    );

    final commandRecords = records.where((record) => record.loggerName == 'BleCommands').toList();
    expect(commandRecords.where((record) => record.level == Level.WARNING).map((record) => record.message),
        contains('Extended command timed out'));
    for (final record in commandRecords) {
      expect(record.message, isNot(contains('owner')));
      expect(record.message, isNot(contains('keycard')));
      expect(record.message, isNot(contains('private-card-material')));
    }
  });

  test('already enabled notifications are not toggled', () async {
    response.isNotifying = true;
    extended.onWrite = (_) async => response.reply('ok');
    await expectLater(sendLsExtendedCommand(device, repo, 'test'), completion('ok'));
    expect(response.notifyCalls, isEmpty);
    expect(response.cancellations, 1);
  });

  test('single-response commands are FIFO through write and response completion', () async {
    final writeGate = Completer<void>();
    extended.onWrite = (write) async {
      if (write.command == 'first') await writeGate.future;
    };
    final first = expectLater(sendLsExtendedCommand(device, repo, 'first'), completion('one'));
    final second = expectLater(sendLsExtendedCommand(device, repo, 'second'), completion('two'));
    await _flush();
    expect(extended.writes.map((write) => write.command), ['first']);
    expect(response.listeners, 1);
    writeGate.complete();
    await _flush();
    expect(extended.writes, hasLength(1), reason: 'Write completion alone does not release the channel');
    response.reply('one');
    await first;
    await _flush();
    expect(extended.writes.map((write) => write.command), ['first', 'second']);
    expect(response.listeners, 1);
    response.reply('two');
    await second;
    expect(response.maxListeners, 1);
    expect(response.cancellations, 2);
  });

  for (final capabilities in [true, false]) {
    test('single/list/single share FIFO (${capabilities ? 'capabilities' : 'keycards'})', () async {
      final first = expectLater(sendLsExtendedCommand(device, repo, 'before'), completion('before:ok'));
      final list = capabilities
          ? expectLater(getLsCapabilitiesCommand(device, repo, 'pm'), completion({'hibernate-for', 'hibernate-cancel'}))
          : expectLater(listKeycardsCommand(device, repo), completion(['AA', 'BB']));
      final last = expectLater(sendLsExtendedCommand(device, repo, 'after'), completion('after:ok'));
      await _flush();
      expect(extended.writes.map((write) => write.command), ['before']);
      response.reply('before:ok');
      await first;
      await _flush();
      final listCommand = capabilities ? 'cap:pm' : 'keycard:list';
      expect(extended.writes.map((write) => write.command), ['before', listCommand]);
      response.reply(capabilities ? 'cap:pm:count:2' : 'keycard:count:2');
      response.reply(capabilities ? 'cap:pm:hibernate-for <duration>' : 'keycard:card:AA');
      await _flush();
      expect(extended.writes, hasLength(2), reason: 'The entire list owns the channel');
      expect(response.listeners, 1);
      response.reply(capabilities ? 'cap:pm:hibernate-cancel' : 'keycard:card:BB');
      await list;
      await _flush();
      expect(extended.writes.map((write) => write.command), ['before', listCommand, 'after']);
      response.reply('after:ok');
      await last;
      expect(response.maxListeners, 1);
      expect(response.cancellations, 3);
      expect(response.notifyCalls, [true]);
    });
  }

  test('expired queued work fails without issuing a late command', () async {
    final gate = Completer<void>();
    final first = withExtendedChannel(() => gate.future);
    await _flush();
    var ran = false;
    final expired = withExtendedChannel(
      () async {
        ran = true;
      },
      maxQueueWait: Duration.zero,
    );
    gate.complete();
    await first;
    await expectLater(expired, throwsA(isA<TimeoutException>()));
    expect(ran, isFalse);
  });

  test('default 12-second queue expiry rejects writes after active transaction cleanup', () async {
    final gatedResponse = _CleanupCharacteristic();
    repo.extendedResponseCharacteristic = gatedResponse;
    addTearDown(() => gatedResponse.values.close());
    final writeGate = Completer<void>();
    extended.onWrite = (_) => writeGate.future;
    final first = sendLsExtendedCommand(device, repo, 'active');
    await _flush();
    final expired = expectLater(sendLsExtendedCommand(device, repo, 'expired-secret'),
        throwsA(isA<TimeoutException>()));
    // Real elapsed time is intentional: the pinned queue uses Stopwatch, not
    // zone timers. A queued expiry must not release an active write or cleanup.
    await Future<void>.delayed(const Duration(milliseconds: 12100));
    expect(extended.writes.map((w) => w.command), ['active']);
    expect(gatedResponse.listeners, 1);
    writeGate.complete();
    await _flush();
    gatedResponse.reply('active:ok');
    await _flush();
    expect(extended.writes.map((w) => w.command), ['active']);
    expect(gatedResponse.listeners, 1, reason: 'Cancellation has not completed');
    final fresh = sendLsExtendedCommand(device, repo, 'fresh');
    await _flush();
    expect(extended.writes, hasLength(1), reason: 'Cleanup still owns the channel');
    gatedResponse.cleanup.complete();
    expect(await first, 'active:ok');
    await expired;
    await _flush();
    expect(extended.writes.map((w) => w.command), ['active', 'fresh']);
    gatedResponse.reply('fresh:ok');
    expect(await fresh, 'fresh:ok');
    expect(gatedResponse.maxListeners, 1);
    expect(gatedResponse.listeners, 0);
  });

  test('transport lifecycle logs at ALL levels exclude command and response contents', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger('BleCommands').onRecord.listen(records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    });
    extended.onWrite = (_) async => response.reply('response-private-value');
    await sendCommand(device, repo, 'basic-private-payload');
    await sendLsExtendedCommand(device, repo, 'custom:token-private payload-private');
    extended.onWrite = (_) async => throw TimeoutException('exception-private');
    expect(await sendLsExtendedCommand(device, repo, 'custom:timeout-private'), isNull);
    final logs = records.map((record) => record.message).join('\n');
    expect(logs, contains('acquired channel'));
    expect(logs, contains('waiting for response'));
    expect(logs, contains('received'));
    expect(logs, contains('timed out'));
    for (final secret in ['basic-private', 'token-private', 'payload-private',
      'response-private', 'exception-private', 'timeout-private']) {
      expect(logs, isNot(contains(secret)), reason: 'No content-bearing labels, even at FINE');
    }
  });

  test('response stream error propagates unchanged and releases FIFO', () async {
    final error = StateError('response stream failed');
    final failed = expectLater(sendLsExtendedCommand(device, repo, 'broken'), throwsA(same(error)));
    final next = expectLater(sendLsExtendedCommand(device, repo, 'next'), completion('next:ok'));
    await _flush();
    expect(extended.writes.map((write) => write.command), ['broken']);
    response.values.addError(error, StackTrace.current);
    await _flush();
    await failed;
    expect(response.cancellations, 1);
    expect(response.listeners, 1);
    expect(extended.writes.map((write) => write.command), ['broken', 'next']);
    response.reply('next:ok');
    await _flush();
    await next;
    expect(response.listeners, 0);
    expect(response.cancellations, 2);
    expect(response.maxListeners, 1);
  });

  test('notification enable failure releases FIFO without creating a listener', () async {
    final error = StateError('notification enable failed');
    final gate = Completer<void>();
    response.notifyGate = gate;
    final failed = expectLater(sendLsExtendedCommand(device, repo, 'broken'), throwsA(same(error)));
    final next = expectLater(sendLsExtendedCommand(device, repo, 'next'), completion('next:ok'));
    extended.onWrite = (_) async {
      expect(response.maxListeners, 1);
      expect(response.cancellations, 0, reason: 'The failed enable never created a listener');
      response.reply('next:ok');
    };
    await _flush();
    expect(response.notifyCalls, [true]);
    expect(response.listeners, 0);
    expect(response.maxListeners, 0);
    expect(extended.writes, isEmpty);
    response.notifyGate = null;
    gate.completeError(error);
    await _flush();
    await failed;
    await next;
    expect(response.notifyCalls, [true, true]);
    expect(extended.writes.map((write) => write.command), ['next']);
    expect(response.listeners, 0);
    expect(response.cancellations, 1);
    expect(response.maxListeners, 1);
  });

  test('write failure cancels listener and releases FIFO to a queued list', () async {
    final gate = Completer<void>();
    final error = StateError('extended write failed');
    extended.onWrite = (write) async {
      if (write.command == 'broken') {
        await gate.future;
        throw error;
      }
      response.reply('keycard:count:1');
      response.reply('keycard:card:recovered');
    };
    final failed = expectLater(sendLsExtendedCommand(device, repo, 'broken'), throwsA(same(error)));
    final recovered = expectLater(listKeycardsCommand(device, repo), completion(['recovered']));
    await _flush();
    expect(extended.writes, hasLength(1));
    expect(response.listeners, 1);
    gate.complete();
    await failed;
    await recovered;
    expect(extended.writes.map((write) => write.command), ['broken', 'keycard:list']);
    expect(response.maxListeners, 1);
    expect(response.cancellations, 2);
    expect(response.notifyCalls, [true]);
  });
}
