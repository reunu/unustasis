import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

final _log = Logger('BleCommands');

/// Writes an ASCII command to the scooter's BLE command characteristic.
void sendCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository characteristicRepository,
  String command, {
  BluetoothCharacteristic? characteristic,
}) {
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

  target.write(ascii.encode(command));
}

/// sends a command to the extended characteristic (only available on librescoot firmware) and waits for a response on the extended response characteristic
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
    final value = await resp.onValueReceived
        .where((v) => v.isNotEmpty)
        .timeout(const Duration(seconds: 10), onTimeout: (sink) => sink.close())
        .first;
    return ascii.decode(value).replaceAll('\x00', '');
  } on StateError {
    // stream closed without emitting a value (timeout)
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

Future<bool> navigateCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:dest ${destination.location.latitude},${destination.location.longitude}${destination.name != null ? ",${destination.name}" : ""}",
  );
  return response == "nav:ok";
}

Future<bool> cancelNavigationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:clear",
  );
  return response == "nav:ok";
}

/// Saves a navigation destination on the scooter. Returns the ID of the saved destination if successful.
Future<String> saveNavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  NavDestination destination,
) async {
  if (destination.name == null || destination.name!.isEmpty) {
    throw "Destination name cannot be empty when storing as favorite";
  }
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:add ${destination.location.latitude},${destination.location.longitude},${destination.name}",
  );

  String? id = response?.split(":").last;
  if (id == null) {
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

    // Use a single subscription to avoid BehaviorSubject replay issues.
    // First message is nav:fav:count:<n>, followed by one message per entry.
    final List<NavDestination> destinations = [];
    int? count;
    await for (final msg in stream) {
      if (count == null) {
        // First message: nav:fav:count:<n>
        count = int.tryParse(msg.split(":").last) ?? 0;
        if (count == 0) break;
      } else {
        // Subsequent messages: nav:fav:<id>:lat,lon,name
        final parts = msg.split(":");
        if (parts.length >= 4) {
          final id = parts[2];
          final coords = parts[3].split(",");
          if (coords.length >= 2) {
            final lat = double.tryParse(coords[0]);
            final lon = double.tryParse(coords[1]);
            if (lat != null && lon != null) {
              final name = coords.length >= 3 ? coords.sublist(2).join(",") : null;
              destinations.add(NavDestination(
                location: LatLng(lat, lon),
                name: name?.isNotEmpty == true ? name : null,
                id: id,
              ));
            }
          }
        }
        if (destinations.length >= count) break;
      }
    }
    return destinations;
  } finally {
    await resp.setNotifyValue(false);
  }
}

Future<bool> navigateFavCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:navigate $id",
  );
  return response == "nav:ok";
}

Future<bool> deleteFavDestinationCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String id,
) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:delete $id",
  );
  return response == "nav:ok";
}

/// Lists keycards registered on the scooter.
/// Expects: keycard:count:<n>, then one keycard:<uid> message per entry.
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

    // Use a single subscription to avoid BehaviorSubject replay issues.
    // First message: keycard:count:<n>, followed by one keycard:<uid> per entry.
    final List<String> uids = [];
    int? count;
    await for (final msg in stream) {
      if (count == null) {
        count = int.tryParse(msg.split(":").last) ?? 0;
        if (count == 0) break;
      } else {
        // format: keycard:<uid>
        final parts = msg.split(":");
        if (parts.length >= 2) {
          final uid = parts.sublist(1).join(":");
          if (uid.isNotEmpty) uids.add(uid);
        }
        if (uids.length >= count) break;
      }
    }
    return uids;
  } finally {
    await resp.setNotifyValue(false);
  }
}
