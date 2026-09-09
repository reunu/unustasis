import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/actions.dart';
import 'package:scooter_core/extended_response.dart';
import 'characteristic_repository.dart';
import 'command_transport.dart';
import 'firmware_queries.dart';

final log = Logger('BleCommands');

Future<void> unlockScooter(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent, void Function()? onWriteIssued}) async {
  await sendCommand(scooter, repo, unlockCommand, isCurrent: isCurrent, onWriteIssued: onWriteIssued);
}

Future<void> lockScooter(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent, void Function()? onWriteIssued}) async {
  await sendCommand(scooter, repo, lockCommand, isCurrent: isCurrent, onWriteIssued: onWriteIssued);
}

enum SeatboxLockFailure { unsupported, unsafeState, expired, redis, unknownOutcome }

class SeatboxLockException implements Exception {
  const SeatboxLockException(this.failure);
  final SeatboxLockFailure failure;
  @override
  String toString() => 'Seatbox lock: ${failure.name}';
}

/// Explicit rider intent only. Probe and dispatch share the existing FIFO and
/// captured session. A successful reply accepts shutdown, not physical locking.
Future<void> lockIgnoringSeatbox(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) => withExtendedChannel(() async {
  checkCommandCurrent(isCurrent);
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw const SeatboxLockException(SeatboxLockFailure.unsupported);
  }
  await ensureExtendedNotify(resp);
  checkCommandCurrent(isCurrent);
  final probe = ExtendedResponseListener(resp.onValueReceived);
  final replies = StreamIterator(probe.responses.timeout(const Duration(seconds: 10)));
  try {
    await sendCommand(scooter, repo, 'cap:lock', characteristic: cmd, isCurrent: isCurrent);
    if (!await replies.moveNext()) {
      throw const SeatboxLockException(SeatboxLockFailure.unsupported);
    }
    if (replies.current == 'cap:lock:error:redis') {
      throw const SeatboxLockException(SeatboxLockFailure.redis);
    }
    if (replies.current != 'cap:lock:count:1' || !await replies.moveNext() ||
        replies.current != 'cap:lock:ignore-seatbox') {
      throw const SeatboxLockException(SeatboxLockFailure.unsupported);
    }
  } on TimeoutException {
    throw const SeatboxLockException(SeatboxLockFailure.unsupported);
  } finally {
    await replies.cancel();
    await probe.cancel();
  }
  checkCommandCurrent(isCurrent);
  final ack = ExtendedResponseListener(resp.onValueReceived);
  var issued = false;
  try {
    await sendCommand(scooter, repo, 'lock:ignore-seatbox', characteristic: cmd,
        isCurrent: isCurrent, onWriteIssued: () => issued = true);
    final response = await ack.responses.first.timeout(const Duration(seconds: 10));
    checkCommandCurrent(isCurrent);
    switch (response) {
      case 'lock:accepted': return;
      case 'lock:error:unsupported':
        throw const SeatboxLockException(SeatboxLockFailure.unsupported);
      case 'lock:error:unsafe-state':
        throw const SeatboxLockException(SeatboxLockFailure.unsafeState);
      case 'lock:error:expired':
        throw const SeatboxLockException(SeatboxLockFailure.expired);
      default:
        throw const SeatboxLockException(SeatboxLockFailure.unknownOutcome);
    }
  } on SeatboxLockException {
    rethrow;
  } catch (_) {
    // Even a failed native write or a lost ACK may follow vehicle acceptance.
    // Never retry or fall back to a basic/force lock.
    if (issued) throw const SeatboxLockException(SeatboxLockFailure.unknownOutcome);
    rethrow;
  } finally {
    await ack.cancel();
  }
});

Future<void> openSeatCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent, void Function()? onWriteIssued}) async {
  await sendCommand(scooter, repo, seatCommand, isCurrent: isCurrent, onWriteIssued: onWriteIssued);
}

Future<void> blinkCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required bool left,
  required bool right,
  bool Function()? isCurrent,
}) async {
  await sendCommand(scooter, repo, blinkerCommand(left, right),
      isCurrent: isCurrent);
}

Future<void> wakeUpCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  await sendCommand(scooter, repo, wakeCommand,
      characteristic: repo.hibernationCommandCharacteristic,
      isCurrent: isCurrent);
}

Future<void> hibernateCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  await sendCommand(scooter, repo, hibernatePowerCommand,
      characteristic: repo.hibernationCommandCharacteristic,
      isCurrent: isCurrent);
}

Future<void> rebootCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  await sendCommand(scooter, repo, rebootPowerCommand,
      characteristic: repo.hibernationCommandCharacteristic,
      isCurrent: isCurrent);
}

Future<void> hardRebootCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  await sendCommand(scooter, repo, hardRebootPowerCommand,
      characteristic: repo.hibernationCommandCharacteristic,
      isCurrent: isCurrent);
}

Future<void> enterUMSModeCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(scooter, repo, usbUmsCommand,
      isCurrent: isCurrent);
  if (response != usbAcknowledgement) {
    log.severe("Failed to enter UMS mode, response: $response");
    throw "Failed to enter UMS mode, response: $response";
  }
  return;
}

Future<void> enterNormalUsbModeCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(scooter, repo, usbNormalCommand,
      isCurrent: isCurrent);
  if (response != usbAcknowledgement) {
    log.severe("Failed to enter normal USB mode, response: $response");
    throw "Failed to enter normal USB mode, response: $response";
  }
  return;
}

/// Counts the number of keycards registered on the scooter by sending a command and listening for the count response.
/// Returns the count as an integer, or null if the command fails or times out.
Future<int?> countKeycardsCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, keycardCountCommand,
      isCurrent: isCurrent);
  if (response != null && response.startsWith("keycard:count:")) {
    return int.tryParse(response.split(":").last);
  }
  return null;
}

/// Lists keycards registered on the scooter.
/// Expects: `keycard:count:<n>`, then one `keycard:card:<uid>` message per entry.
Future<List<String>> listKeycardsCommand(
        BluetoothDevice? scooter, CharacteristicRepository repo,
        {bool Function()? isCurrent}) =>
    withExtendedChannel(() async {
      if (scooter == null || scooter.isDisconnected) {
        throw "Scooter not connected!";
      }
      final cmd = repo.extendedCommandCharacteristic;
      final resp = repo.extendedResponseCharacteristic;
      if (cmd == null || resp == null) {
        throw "Extended command characteristics not available";
      }

      checkCommandCurrent(isCurrent);
      await ensureExtendedNotify(resp);
      checkCommandCurrent(isCurrent);
      final listener = ExtendedResponseListener(resp.onValueReceived);
      try {
        await sendCommand(scooter, repo, keycardListCommand,
            characteristic: cmd, isCurrent: isCurrent);
        final stream = listener.responses.timeout(const Duration(seconds: 10));
        return await readExtendedList(stream, (msg) {
          // format: keycard:card:<uid>
          final parts = msg.split(":");
          if (parts.length >= 3 &&
              parts[0] == "keycard" &&
              parts[1] == "card") {
            final uid = parts.sublist(2).join(":");
            return uid.isNotEmpty ? uid : null;
          }
          log.warning("listKeycardsCommand: unexpected message format: '$msg'");
          return null;
        });
      } finally {
        await listener.cancel();
      }
    });

Future<void> deleteKeycardCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String uid,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, deleteKeycardPayload(uid),
      isCurrent: isCurrent);
  if (response != keycardAcknowledgement) {
    log.severe("Failed to delete keycard, response: $response");
    throw "Failed to delete keycard, response: $response";
  }
  return;
}

Future<void> addKeycardCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String uid,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, addKeycardPayload(uid),
      isCurrent: isCurrent);
  if (response != keycardAcknowledgement) {
    log.severe("Failed to add keycard, response: $response");
    throw "Failed to add keycard, response: $response";
  }
  return;
}

/// Sets the auto-standby timer on the scooter. [time] is the duration until the scooter automatically enters standby mode when idle.
/// 0 = disabled
Future<void> setAutoStandbyTimeCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, Duration time,
    {bool Function()? isCurrent}) async {
  await setLsSettingCommand(
      scooter, repo, lsKeyAutoStandbySeconds, autoStandbyValue(time),
      isCurrent: isCurrent);
}

Future<void> setAutoHibernateTimeCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, Duration time,
    {bool Function()? isCurrent}) async {
  final seconds = time.inSeconds;
  await setLsSettingCommand(
      scooter, repo, lsKeyHibernateTimer, seconds.toString(),
      isCurrent: isCurrent);
}

/// Sets the APN the scooter's modem attaches with.
///
/// Surrounding whitespace is trimmed. An empty APN is rejected here rather than
/// sent on, so that emptying the text field cannot silently drop the scooter
/// onto operator defaults. Use [clearCellularApnCommand] to do that on purpose.
Future<void> setCellularApnCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String apn,
    {bool Function()? isCurrent}) async {
  final trimmed = apn.trim();
  final problem = checkApn(trimmed);
  if (problem != null) {
    log.warning("Refusing to send APN '$apn': ${problem.name}");
    throw "Invalid APN (${problem.name})";
  }
  await setLsSettingCommand(scooter, repo, lsKeyCellularApn, trimmed,
      isCurrent: isCurrent);
}

/// Clears the configured APN so the modem falls back to whatever the SIM
/// operator hands out.
///
/// Sends the prefix and nothing after it. The trailing space in
/// [apnCommandPrefix] is load-bearing: the firmware splits the payload on the
/// first space and answers `config:error:missing value` when there is no second
/// field, so `config:apn ` sets an empty value where `config:apn` would fail.
/// Only the value gets trimmed on the way in, never the command.
Future<void> clearCellularApnCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(scooter, repo, apnCommandPrefix,
      isCurrent: isCurrent);
  if (response != apnAcknowledgement) {
    log.severe("Failed to clear APN, response: $response");
    throw "Failed to clear APN, response: $response";
  }
  return;
}

/// Hibernates the scooter and arms a wake timer (librescoot pm capability).
/// [wakeAfter] must be positive; firmware silently clamps to its configured
/// maximum (7 days by default).
Future<void> hibernateForCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, Duration wakeAfter,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, hibernateForPayload(wakeAfter),
      isCurrent: isCurrent);
  if (response != pmAcknowledgement) {
    log.severe("Failed to hibernate with wake timer, response: $response");
    throw "Failed to hibernate, response: $response";
  }
}

/// Cancels a pending hibernate-for wake timer.
Future<void> hibernateCancelCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, hibernateCancelPowerCommand,
      isCurrent: isCurrent);
  if (response != pmAcknowledgement) {
    log.severe("Failed to cancel hibernation, response: $response");
    throw "Failed to cancel hibernation, response: $response";
  }
}

/// Asks the scooter to forget this phone, clearing the scooter's half of the
/// bond. Only the caller's own bond can be dropped this way: the scooter
/// resolves the peer from the live connection, so there is nothing to pass and
/// no way to reach anyone else's bond.
///
/// Send this while still connected and before dropping the phone's own bond.
/// The command only travels over the authenticated link, and the scooter
/// disconnects to carry the delete out, so there is no second chance.
///
/// The reply means the command was accepted, not that the bond is gone: nothing
/// on the vehicle exposes a peer list. The scooter dropping the link afterwards
/// is the observable part, so callers should wait for it.
///
/// Throws if the scooter refuses or never answers. Needs librescoot 1.3 with
/// nRF firmware v2.8.0-ls or later; probe `cap:ble` for "forget" first.
Future<void> forgetBondCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(scooter, repo, bondForgetCommand,
      isCurrent: isCurrent);
  if (response != bondForgetAcknowledgement) {
    log.warning("Scooter would not forget this phone, response: $response");
    throw "Failed to forget the scooter side of the bond, response: $response";
  }
}
