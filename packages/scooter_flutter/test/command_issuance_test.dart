import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_flutter/command_transport.dart';
import 'package:scooter_flutter/scooter_flutter.dart'
    show CharacteristicRepository;

class _Device extends Fake implements BluetoothDevice {
  @override
  bool isDisconnected = false;
}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  _Characteristic(this.trace);
  final List<String> trace;
  bool synchronousFailure = false;
  bool asynchronousFailure = false;
  @override
  Future<void> write(List<int> bytes,
      {bool withoutResponse = false,
      bool allowLongWrite = false,
      int timeout = 15}) {
    trace.add('write:${String.fromCharCodes(bytes)}');
    if (synchronousFailure) throw StateError('native invocation failed');
    if (asynchronousFailure) {
      return Future.error(StateError('native ACK failed'));
    }
    return Future.value();
  }
}

void main() {
  test('an unresponsive extended channel fails without spending the timeout',
      () async {
    final trace = <String>[];
    final device = _Device();
    final repo = CharacteristicRepository(device)
      ..extendedCommandCharacteristic = _Characteristic(trace)
      ..extendedResponseCharacteristic = _Characteristic(trace);
    // Two commands went unanswered, which is how the transport learns that
    // nothing on this scooter replies.
    repo.noteSilentExtendedCommand();
    repo.noteSilentExtendedCommand();

    final stopwatch = Stopwatch()..start();
    final response = await sendLsExtendedCommand(device, repo, 'cap:ext');
    stopwatch.stop();

    expect(response, isNull);
    expect(trace, isEmpty, reason: 'nothing is written to a dead channel');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  for (final rejection in [
    'no-device',
    'disconnected',
    'missing-command',
    'stale',
    'non-ASCII'
  ]) {
    test('sendCommand $rejection is known before native issuance', () async {
      final trace = <String>[];
      final device = _Device()..isDisconnected = rejection == 'disconnected';
      final repo = CharacteristicRepository(device)
        ..commandCharacteristic =
            rejection == 'missing-command' ? null : _Characteristic(trace);
      await expectLater(
          sendCommand(rejection == 'no-device' ? null : device, repo,
              rejection == 'non-ASCII' ? 'café' : 'scooter:state unlock',
              isCurrent: () => rejection != 'stale',
              onWriteIssued: () => trace.add('issued')),
          throwsA(anything));
      expect(trace, isEmpty);
    });
  }
  for (final mode in ['success', 'sync-error', 'async-error']) {
    test('sendCommand marks possible issuance before $mode native result',
        () async {
      final trace = <String>[];
      final device = _Device();
      final command = _Characteristic(trace)
        ..synchronousFailure = mode == 'sync-error'
        ..asynchronousFailure = mode == 'async-error';
      final repo = CharacteristicRepository(device)
        ..commandCharacteristic = command;
      final result = sendCommand(device, repo, 'scooter:state unlock',
          onWriteIssued: () => trace.add('issued'));
      if (mode == 'success') {
        await result;
      } else {
        await expectLater(result, throwsStateError);
      }
      expect(trace, ['issued', 'write:scooter:state unlock']);
    });
  }
}
