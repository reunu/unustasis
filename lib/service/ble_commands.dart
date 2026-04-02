import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

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
