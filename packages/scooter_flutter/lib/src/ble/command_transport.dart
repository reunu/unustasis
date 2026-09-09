import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/extended_response.dart';

import 'characteristic_repository.dart';

final _log = Logger('BleCommands');

Future<void> _extendedChannelQueue = Future.value();

/// Serializes access to the extended command/response characteristics so that
/// concurrent callers can't consume each other's responses or toggle the
/// notify state underneath each other.
Future<T> withExtendedChannel<T>(Future<T> Function() action) {
  final result = _extendedChannelQueue.then((_) => action());
  _extendedChannelQueue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Turns notifications on for the extended response characteristic unless
/// they're already on.
///
/// `isNotifying` is derived from the cached CCCD value, which flutter_blue_plus
/// clears on disconnect, so the subscription lives for exactly one connection.
/// Toggling it per command cost two extra CCCD writes each time and dropped
/// any response that arrived while notify was off.
Future<void> ensureExtendedNotify(BluetoothCharacteristic resp) async {
  if (resp.isNotifying) return;
  await resp.setNotifyValue(true);
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
  _log.fine("Sending command: $command");
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
  // From this point even a synchronous native write error is ambiguous. This
  // optional observation lets explicit requests retain only definite non-writes.
  onWriteIssued?.call();
  await target.write(bytes, allowLongWrite: allowLongWrite);
}

/// Sends a command to the extended characteristic (only available on librescoot
/// firmware) and waits for a single response on the extended response
/// characteristic. Returns null on timeout.
Future<String?> sendLsExtendedCommand(
        BluetoothDevice? scooter, CharacteristicRepository repo, String command,
        {bool Function()? isCurrent}) =>
    withExtendedChannel(() => _sendLsExtendedCommandUnguarded(
        scooter, repo, command,
        isCurrent: isCurrent));

Future<String?> _sendLsExtendedCommandUnguarded(
    BluetoothDevice? scooter, CharacteristicRepository repo, String command,
    {bool Function()? isCurrent}) async {
  checkCommandCurrent(isCurrent);
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await ensureExtendedNotify(resp);
  checkCommandCurrent(isCurrent);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, command,
        characteristic: cmd, allowLongWrite: true, isCurrent: isCurrent);
    return await listener.responses.first.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    _log.warning(
        "sendLsExtendedCommand: timeout waiting for response to '$command'");
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
