import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

final log = Logger('BleCommands');

/// Librescoot settings keys for scheduled hibernation.
const String lsKeyScheduledHibernateEnabled = "pm.scheduled-hibernate-enabled";
const String lsKeyScheduledHibernateCron = "pm.scheduled-hibernate-cron";
const String lsKeyScheduledHibernateDuration = "pm.scheduled-hibernate-duration";

Future<void> _extendedChannelQueue = Future.value();

/// Serializes access to the extended command/response characteristics so that
/// concurrent callers can't consume each other's responses or toggle the
/// notify state underneath each other.
Future<T> _withExtendedChannel<T>(Future<T> Function() action) {
  final result = _extendedChannelQueue.then((_) => action());
  _extendedChannelQueue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Reads a counted list from an extended response [stream].
///
/// Expects the first message to carry the count as its last colon-separated
/// segment (e.g. `keycard:count:3`), followed by that many entry messages.
/// [parseEntry] converts each entry message to [T]; returning null skips it.
Future<List<T>> _readExtendedList<T>(
  Stream<String> stream,
  T? Function(String msg) parseEntry,
) async {
  final List<T> results = [];
  int? count;
  await for (final msg in stream) {
    if (count == null) {
      count = int.tryParse(msg.split(':').last) ?? 0;
      if (count == 0) break;
    } else {
      final entry = parseEntry(msg);
      if (entry != null) results.add(entry);
      if (results.length >= count) break;
    }
  }
  return results;
}

/// Writes an ASCII command to the scooter's BLE command characteristic.
Future<void> sendCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository characteristicRepository,
  String command, {
  BluetoothCharacteristic? characteristic,
}) async {
  log.fine("Sending command: $command");
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

  await target.write(ascii.encode(command));
}

/// Sends a command to the extended characteristic (only available on librescoot
/// firmware) and waits for a single response on the extended response
/// characteristic. Returns null on timeout.
Future<String?> sendLsExtendedCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String command,
) =>
    _withExtendedChannel(() => _sendLsExtendedCommandUnguarded(scooter, repo, command));

Future<String?> _sendLsExtendedCommandUnguarded(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String command,
) async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await resp.setNotifyValue(true);
  try {
    await sendCommand(scooter, repo, command, characteristic: cmd);
    return await resp.onValueReceived
        .where((v) => v.isNotEmpty)
        .map((v) => ascii.decode(v).replaceAll('\x00', ''))
        .timeout(const Duration(seconds: 10), onTimeout: (sink) => sink.close())
        .first;
  } on StateError {
    log.warning("sendLsExtendedCommand: timeout waiting for response to '$command'");
    return null;
  } finally {
    await resp.setNotifyValue(false);
  }
}

/// Sends a power command to a scooter by ID, connecting first if needed.
Future<void> sendStaticPowerCommand(String id, String command) async {
  BluetoothDevice scooter = BluetoothDevice.fromId(id);
  if (scooter.isDisconnected) {
    await scooter.connect();
  }
  await scooter.discoverServices();
  BluetoothCharacteristic? commandCharacteristic = CharacteristicRepository.findCharacteristic(
    scooter,
    "9a590000-6e67-5d0d-aab9-ad9126b66f91",
    "9a590001-6e67-5d0d-aab9-ad9126b66f91",
  );
  await commandCharacteristic!.write(ascii.encode(command));
}

Future<void> unlockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) async {
  await sendCommand(scooter, repo, "scooter:state unlock");
  HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
    eventType: EventType.unlock,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> lockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
  dynamic lastLocation,
}) async {
  await sendCommand(scooter, repo, "scooter:state lock");
  HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
    eventType: EventType.lock,
    scooterId: scooter!.remoteId.toString(),
    location: lastLocation,
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> openSeatCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) async {
  await sendCommand(scooter, repo, "scooter:seatbox open");
  StatisticsHelper().logEvent(
    eventType: EventType.openSeat,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> blinkCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required bool left,
  required bool right,
}) async {
  if (left && !right) {
    await sendCommand(scooter, repo, "scooter:blinker left");
  } else if (!left && right) {
    await sendCommand(scooter, repo, "scooter:blinker right");
  } else if (left && right) {
    await sendCommand(scooter, repo, "scooter:blinker both");
  } else {
    await sendCommand(scooter, repo, "scooter:blinker off");
  }
}

Future<void> wakeUpCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "wakeup",
    characteristic: repo.hibernationCommandCharacteristic,
  );
  StatisticsHelper().logEvent(
    eventType: EventType.wakeUp,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> hibernateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "hibernate",
    characteristic: repo.hibernationCommandCharacteristic,
  );
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> rebootCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "reboot",
    characteristic: repo.hibernationCommandCharacteristic,
  );
}

Future<void> hardRebootCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await sendCommand(
    scooter,
    repo,
    "hard-reboot",
    characteristic: repo.hibernationCommandCharacteristic,
  );
}

Future<void> enterUMSModeCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "usb:ums",
  );
  if (response != "usb:ok") {
    log.severe("Failed to enter UMS mode, response: $response");
    throw "Failed to enter UMS mode, response: $response";
  }
  return;
}

Future<void> enterNormalUsbModeCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "usb:normal",
  );
  if (response != "usb:ok") {
    log.severe("Failed to enter normal USB mode, response: $response");
    throw "Failed to enter normal USB mode, response: $response";
  }
  return;
}

Future<void> navigateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:dest ${destination.location.latitude},${destination.location.longitude}${destination.name != null ? ",${destination.name}" : ""}",
  );
  if (response != "nav:ok") {
    log.severe("Failed to navigate, response: $response");
    throw "Failed to navigate, response: $response";
  }
  return;
}

Future<void> cancelNavigationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:clear",
  );
  if (response != "nav:ok") {
    log.severe("Failed to cancel navigation, response: $response");
    throw "Failed to cancel navigation, response: $response";
  }
  return;
}

/// Saves a navigation destination on the scooter. Returns the ID of the saved destination if successful.
Future<String> saveNavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  if (destination.name == null || destination.name!.isEmpty) {
    log.warning("Destination name cannot be empty when storing as favorite");
    throw "Destination name cannot be empty when storing as favorite";
  }
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:add ${destination.location.latitude},${destination.location.longitude},${destination.name}",
  );

  String? id = response?.split(":").last;
  if (id == null) {
    log.severe("Failed to save navigation destination, response: $response");
    throw "Failed to save navigation destination";
  }
  return id;
}

Future<List<NavDestination>> listFavDestinationsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) =>
    _withExtendedChannel(() async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await resp.setNotifyValue(true);
  try {
    await sendCommand(scooter, repo, "nav:fav:list", characteristic: cmd);
    final stream = resp.onValueReceived
        .where((v) => v.isNotEmpty)
        .map((v) => ascii.decode(v).replaceAll('\x00', ''))
        .timeout(const Duration(seconds: 10));
    return await _readExtendedList(stream, (msg) {
      // format: nav:fav:<id>:lat,lon[,name]
      final parts = msg.split(":");
      if (parts.length < 4) return null;
      final coords = parts[3].split(",");
      if (coords.length < 2) return null;
      final lat = double.tryParse(coords[0]);
      final lon = double.tryParse(coords[1]);
      if (lat == null || lon == null) return null;
      final name = coords.length >= 3 ? coords.sublist(2).join(",") : null;
      return NavDestination(
        location: LatLng(lat, lon),
        name: name?.isNotEmpty == true ? name : null,
        id: parts[2],
      );
    });
  } finally {
    await resp.setNotifyValue(false);
  }
});

Future<void> navigateFavCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:navigate $id",
  );
  if (response != "nav:ok") {
    log.severe("Failed to navigate to favorite destination, response: $response");
    throw "Failed to navigate to favorite destination, response: $response";
  }
  return;
}

Future<void> deleteFavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:delete $id",
  );
  if (response != "nav:ok") {
    log.severe("Failed to delete favorite destination, response: $response");
    throw "Failed to delete favorite destination, response: $response";
  }
  return;
}

/// Counts the number of keycards registered on the scooter by sending a command and listening for the count response.
/// Returns the count as an integer, or null if the command fails or times out.
Future<int?> countKeycardsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:count",
  );
  if (response != null && response.startsWith("keycard:count:")) {
    return int.tryParse(response.split(":").last);
  }
  return null;
}

/// Lists keycards registered on the scooter.
/// Expects: keycard:count:<n>, then one keycard:card:<uid> message per entry.
Future<List<String>> listKeycardsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) =>
    _withExtendedChannel(() async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await resp.setNotifyValue(true);
  try {
    await sendCommand(scooter, repo, "keycard:list", characteristic: cmd);
    final stream = resp.onValueReceived
        .where((v) => v.isNotEmpty)
        .map((v) => ascii.decode(v).replaceAll('\x00', ''))
        .timeout(const Duration(seconds: 10));
    return await _readExtendedList(stream, (msg) {
      // format: keycard:card:<uid>
      final parts = msg.split(":");
      if (parts.length >= 3 && parts[0] == "keycard" && parts[1] == "card") {
        final uid = parts.sublist(2).join(":");
        return uid.isNotEmpty ? uid : null;
      }
      log.warning("listKeycardsCommand: unexpected message format: '$msg'");
      return null;
    });
  } finally {
    await resp.setNotifyValue(false);
  }
});

Future<void> deleteKeycardCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String uid,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:remove:$uid",
  );
  if (response != "keycard:ok") {
    log.severe("Failed to delete keycard, response: $response");
    throw "Failed to delete keycard, response: $response";
  }
  return;
}

Future<void> addKeycardCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String uid,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "keycard:add:$uid",
  );
  if (response != "keycard:ok") {
    log.severe("Failed to add keycard, response: $response");
    throw "Failed to add keycard, response: $response";
  }
  return;
}

/// Sets the auto-standby timer on the scooter. [time] is the duration until the scooter automatically enters standby mode when idle.
/// 0 = disabled
Future<void> setAutoStandbyTimeCommand(BluetoothDevice? scooter, CharacteristicRepository repo, Duration time) async {
  final seconds = time.inSeconds;
  if (seconds < 0) {
    log.warning("Auto-standby time cannot be negative");
    throw "Auto-standby time cannot be negative";
  }
  if (seconds > 3600) {
    log.warning("Auto-standby time cannot be greater than 1 hour");
    throw "Auto-standby time cannot be greater than 1 hour";
  }
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "config:auto-standby-seconds $seconds",
  );
  if (response != "config:ok") {
    log.severe("Failed to set auto-standby time, response: $response");
    throw "Failed to set auto-standby time, response: $response";
  }
  return;
}

Future<void> setAutoHibernateTimeCommand(BluetoothDevice? scooter, CharacteristicRepository repo, Duration time) async {
  final seconds = time.inSeconds;
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "config:hibernate-timer $seconds",
  );
  if (response != "config:ok") {
    log.severe("Failed to set auto-hibernate time, response: $response");
    throw "Failed to set auto-hibernate time, response: $response";
  }
  return;
}

/// Hibernates the scooter and arms a wake timer (librescoot pm capability).
/// [wakeAfter] must be positive; firmware silently clamps to its configured
/// maximum (7 days by default).
Future<void> hibernateForCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  Duration wakeAfter,
) async {
  if (wakeAfter <= Duration.zero) {
    throw "Hibernate wake timer must be positive";
  }
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "pm:hibernate-for ${wakeAfter.inSeconds}s",
  );
  if (response != "pm:ok") {
    log.severe("Failed to hibernate with wake timer, response: $response");
    throw "Failed to hibernate, response: $response";
  }
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

/// Cancels a pending hibernate-for wake timer.
Future<void> hibernateCancelCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "pm:hibernate-cancel");
  if (response != "pm:ok") {
    log.severe("Failed to cancel hibernation, response: $response");
    throw "Failed to cancel hibernation, response: $response";
  }
}

/// Queries the scooter's power-management capabilities (e.g. "hibernate-for",
/// "hibernate-cancel"). Returns an empty set on firmware that doesn't support
/// the capability query (error response or timeout).
Future<Set<String>> getPmCapabilitiesCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) =>
    _withExtendedChannel(() async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await resp.setNotifyValue(true);
  try {
    await sendCommand(scooter, repo, "cap:pm", characteristic: cmd);
    final stream = resp.onValueReceived
        .where((v) => v.isNotEmpty)
        .map((v) => ascii.decode(v).replaceAll('\x00', ''))
        .timeout(const Duration(seconds: 10));
    // format: cap:pm:count:<n>, then cap:pm:<command>[ <args>] per entry.
    // Error responses fail the count parse and yield an empty list.
    final entries = await _readExtendedList(stream, (msg) {
      if (!msg.startsWith("cap:pm:")) return null;
      final name = msg.substring("cap:pm:".length).split(" ").first;
      return name.isNotEmpty ? name : null;
    });
    return entries.toSet();
  } on TimeoutException {
    log.info("getPmCapabilitiesCommand: timeout, assuming no pm capabilities");
    return <String>{};
  } finally {
    await resp.setNotifyValue(false);
  }
});

/// Reads a librescoot settings key via the generic get command. Returns null
/// if the key or the get command itself is unsupported (or on timeout), and
/// "" if the key exists but is unset.
Future<String?> getLsSettingCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String key,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "get:$key");
  final prefix = "get:$key:";
  if (response == null || !response.startsWith(prefix)) {
    // covers "get:error:unknown key", "error:unknown command" and timeouts
    log.info("getLsSettingCommand: '$key' unsupported or failed, response: $response");
    return null;
  }
  // the value is everything after the first colon following the key; it may
  // itself contain spaces or colons (e.g. cron expressions)
  return response.substring(prefix.length);
}

/// Writes a librescoot settings key. [value] must not be empty (the firmware
/// rejects empty values).
Future<void> setLsSettingCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String key,
  String value,
) async {
  if (value.isEmpty) {
    throw "Setting value must not be empty";
  }
  final response = await sendLsExtendedCommand(scooter, repo, "set:$key:$value");
  if (response != "set:ok:$key") {
    log.severe("Failed to set $key, response: $response");
    throw "Failed to set $key, response: $response";
  }
}
