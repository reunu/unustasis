import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

final log = Logger('BleCommands');

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
void sendCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository characteristicRepository,
  String command, {
  BluetoothCharacteristic? characteristic,
}) {
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

  target.write(ascii.encode(command));
}

/// Sends a command to the extended characteristic (only available on librescoot
/// firmware) and waits for a single response on the extended response
/// characteristic. Returns null on timeout.
Future<String?> sendLsExtendedCommand(
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
    sendCommand(scooter, repo, command, characteristic: cmd);
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

void unlockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) {
  sendCommand(scooter, repo, "scooter:state unlock");
  HapticFeedback.heavyImpact();
  StatisticsHelper().logEvent(
    eventType: EventType.unlock,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

void lockScooter(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
  dynamic lastLocation,
}) {
  sendCommand(scooter, repo, "scooter:state lock");
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

void openSeatCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required int? primarySOC,
  required int? secondarySOC,
  required EventSource source,
}) {
  sendCommand(scooter, repo, "scooter:seatbox open");
  StatisticsHelper().logEvent(
    eventType: EventType.openSeat,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

void blinkCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  required bool left,
  required bool right,
}) {
  if (left && !right) {
    sendCommand(scooter, repo, "scooter:blinker left");
  } else if (!left && right) {
    sendCommand(scooter, repo, "scooter:blinker right");
  } else if (left && right) {
    sendCommand(scooter, repo, "scooter:blinker both");
  } else {
    sendCommand(scooter, repo, "scooter:blinker off");
  }
}

void wakeUpCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) {
  sendCommand(
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

void hibernateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) {
  sendCommand(
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
    sendCommand(scooter, repo, "nav:fav:list", characteristic: cmd);
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
}

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
    sendCommand(scooter, repo, "keycard:list", characteristic: cmd);
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
}

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
