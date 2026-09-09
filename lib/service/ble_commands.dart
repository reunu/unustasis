import 'dart:convert';

import 'package:scooter_flutter/action_commands.dart' as action_commands;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../domain/nav_destination.dart';
import 'package:scooter_flutter/navigation_commands.dart' as navigation_commands;
export 'package:scooter_flutter/navigation_commands.dart' hide listFavDestinationsCommand;
import '../domain/statistics_helper.dart';
import '../infrastructure/characteristic_repository.dart';

// Preserve the legacy command API while protocol consumers migrate to core.
export 'package:scooter_core/extended_response.dart';
export 'package:scooter_core/telemetry.dart'
    show lsKeyScheduledHibernateEnabled, lsKeyBatteryKeepActiveOnSeatboxOpen;
export 'package:scooter_flutter/command_transport.dart' show sendCommand, sendLsExtendedCommand;
export 'package:scooter_flutter/firmware_queries.dart';
export 'package:scooter_core/actions.dart';
export 'package:scooter_flutter/action_commands.dart' hide unlockScooter, lockScooter, openSeatCommand, wakeUpCommand, hibernateCommand, hibernateForCommand;

final log = Logger('BleCommands');

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
  await action_commands.unlockScooter(scooter, repo);
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
  await action_commands.lockScooter(scooter, repo);
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
  await action_commands.openSeatCommand(scooter, repo);
  StatisticsHelper().logEvent(
    eventType: EventType.openSeat,
    scooterId: scooter!.remoteId.toString(),
    soc1: primarySOC,
    soc2: secondarySOC,
    source: source,
  );
}

Future<void> wakeUpCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  await action_commands.wakeUpCommand(scooter, repo);
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
  await action_commands.hibernateCommand(scooter, repo);
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<void> hibernateForCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  Duration wakeAfter,
) async {
  await action_commands.hibernateForCommand(scooter, repo, wakeAfter);
  StatisticsHelper().logEvent(
    eventType: EventType.hibernate,
    scooterId: scooter!.remoteId.toString(),
    source: EventSource.app,
  );
}

Future<List<NavDestination>> listFavDestinationsCommand(
  BluetoothDevice? scooter, CharacteristicRepository repo) async =>
    (await navigation_commands.listFavDestinationsCommand(scooter, repo))
      .map(NavDestination.fromDestination).toList();
