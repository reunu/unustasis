import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/extended_response.dart';

import 'characteristic_repository.dart';

final _log = Logger('BleCommands');

Future<void> _extendedChannelQueue = Future.value();

/// Serializes access to the extended command/response characteristics so that
/// concurrent callers can't consume each other's responses or toggle the
/// notify state underneath each other.
Future<T> withExtendedChannel<T>(
  Future<T> Function() action, {
  Duration maxQueueWait = const Duration(seconds: 12),
}) {
  final queuedFor = Stopwatch()..start();
  final result = _extendedChannelQueue.then((_) {
    if (queuedFor.elapsed >= maxQueueWait) {
      throw TimeoutException(
          'Extended command expired while waiting for the channel');
    }
    return action();
  });
  _extendedChannelQueue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Enables the extended response subscription once per connection, without
/// trusting the cached CCCD value.
Future<void> ensureExtendedNotify(
  CharacteristicRepository repo,
  BluetoothCharacteristic resp, {
  bool Function()? isCurrent,
}) async {
  checkCommandCurrent(isCurrent);
  if (repo.extendedNotifyVerified) return;
  try {
    await resp.setNotifyValue(true);
  } catch (e) {
    repo.noteGattRejection(e, 'Extended response notify-enable');
    rethrow;
  }
  // Only after it worked, so a refused enable is retried by the next command.
  repo.extendedNotifyVerified = true;
  if (Platform.isAndroid) await verifyExtendedNotify(repo, resp);
}

/// A subscription that did not take means the phone's table is stale.
Future<void> verifyExtendedNotify(
    CharacteristicRepository repo, BluetoothCharacteristic resp) async {
  final cccd = _cccdOf(resp);
  if (cccd == null) return;
  try {
    final value = await cccd.read();
    final enabled = value.length == 2 &&
        value[1] == 0 &&
        (value[0] & ~0x03) == 0 &&
        ((value[0] & 0x01) == 0 || resp.properties.notify) &&
        ((value[0] & 0x02) == 0 || resp.properties.indicate) &&
        (value[0] & 0x03) != 0;
    if (!enabled) {
      repo.noteStaleGattTable(
          'the extended response subscription did not enable cleanly');
    }
  } catch (e) {
    _log.fine('Could not read the extended response CCCD back: $e');
  }
}

/// How long an extended command waits for its answer.
const Duration extendedResponseTimeout = Duration(seconds: 5);

final Guid _cccdUuid = Guid("00002902-0000-1000-8000-00805f9b34fb");

BluetoothDescriptor? _cccdOf(BluetoothCharacteristic resp) {
  try {
    return resp.descriptors.firstWhere((d) => d.descriptorUuid == _cccdUuid);
  } catch (_) {
    return null;
  }
}

/// Writes an ASCII command to the scooter's BLE command characteristic.
Future<void> sendCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository characteristicRepository,
  String command, {
  BluetoothCharacteristic? characteristic,
  bool allowLongWrite = false,
  bool Function()? isCurrent,
  void Function()? onWriteIssued,
}) async {
  checkCommandCurrent(isCurrent);
  if (scooter == null) {
    throw "Scooter not found!";
  }
  if (scooter.isDisconnected) {
    throw "Scooter disconnected!";
  }

  var target = characteristic ?? characteristicRepository.commandCharacteristic;

  if (target == null) {
    throw "Could not send command, move closer or reconnect";
  }

  final bytes = ascii.encode(command);
  _log.fine('Sending command (${bytes.length} bytes)');
  // From this point even a synchronous native write error is ambiguous. This
  // optional observation lets explicit requests retain only definite non-writes.
  onWriteIssued?.call();
  try {
    await target.write(bytes, allowLongWrite: allowLongWrite);
  } catch (e) {
    characteristicRepository.noteGattRejection(e, 'Command write');
    rethrow;
  }
}

/// Sends a command to the extended characteristic (only available on librescoot
/// firmware) and waits for a single response on the extended response
/// characteristic. Returns null on timeout.
Future<String?> sendLsExtendedCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String command, {
  bool Function()? isCurrent,
  Duration responseTimeout = extendedResponseTimeout,
}) =>
    withExtendedChannel(() => _sendLsExtendedCommandUnguarded(
          scooter,
          repo,
          command,
          isCurrent: isCurrent,
          responseTimeout: responseTimeout,
        ));

Future<String?> _sendLsExtendedCommandUnguarded(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String command, {
  bool Function()? isCurrent,
  required Duration responseTimeout,
}) async {
  checkCommandCurrent(isCurrent);
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }
  // Writing anyway spends the whole response timeout to learn nothing.
  if (repo.gattTableMismatch) {
    throw "Bluetooth services on this phone are out of date, forget the scooter and pair again";
  }
  // Nothing is answering on this channel, so report the verdict a timeout would
  // have produced without the wait. Every screen that reads settings otherwise
  // waits out five seconds per field, one after another.
  if (repo.extendedChannelUnresponsive) {
    _log.info('Extended command skipped, channel has not answered');
    return null;
  }

  _log.info(
      'Extended command acquired channel; notifications=${resp.isNotifying}');
  try {
    await ensureExtendedNotify(repo, resp, isCurrent: isCurrent);
  } catch (e) {
    rethrow;
  }
  checkCommandCurrent(isCurrent);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, command,
        characteristic: cmd, allowLongWrite: true, isCurrent: isCurrent);
    _log.info('Extended command written; waiting for response');
    final response = await listener.responses
        .map((response) {
          repo.noteExtendedResponse();
          return response;
        })
        .first
        .timeout(responseTimeout);
    _log.info(
        'Extended command received ${utf8.encode(response).length} bytes');
    return response;
  } on TimeoutException {
    _log.warning('Extended command timed out');
    repo.noteSilentExtendedCommand();
    return null;
  } finally {
    await listener.cancel();
  }
}

void checkCommandCurrent(bool Function()? isCurrent) {
  if (isCurrent != null && !isCurrent()) {
    throw StateError("Action session expired");
  }
}
