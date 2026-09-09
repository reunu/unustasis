import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/navigation.dart';
import 'package:scooter_core/extended_response.dart';
import 'characteristic_repository.dart';
import 'command_transport.dart';

final _log = Logger('BleCommands');

Future<void> navigateCommand(BluetoothDevice? scooter,
    CharacteristicRepository repo, NavigationDestination destination,
    {bool Function()? isCurrent}) async {
  final command = navigateDestinationCommand(destination);
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    command,
    isCurrent: isCurrent,
  );
  if (response != "nav:ok") {
    _log.severe("Failed to navigate, response: $response");
    throw "Failed to navigate, response: $response";
  }
  return;
}

Future<void> cancelNavigationCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:clear",
    isCurrent: isCurrent,
  );
  if (response != "nav:ok") {
    _log.severe("Failed to cancel navigation, response: $response");
    throw "Failed to cancel navigation, response: $response";
  }
  return;
}

/// Saves a navigation destination on the scooter. Returns the ID of the saved destination if successful.
Future<String> saveNavDestinationCommand(BluetoothDevice? scooter,
    CharacteristicRepository repo, NavigationDestination destination,
    {bool Function()? isCurrent}) async {
  final command = saveFavoriteCommand(destination);
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    command,
    isCurrent: isCurrent,
  );

  String? id = response?.split(":").last;
  if (id == null) {
    _log.severe("Failed to save navigation destination, response: $response");
    throw "Failed to save navigation destination";
  }
  return id;
}

Future<List<NavigationDestination>> listFavDestinationsCommand(
        BluetoothDevice? scooter, CharacteristicRepository repo,
        {bool Function()? isCurrent}) =>
    withExtendedChannel(() async {
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
        await sendCommand(scooter, repo, "nav:fav:list",
            characteristic: cmd, isCurrent: isCurrent);
        final stream = listener.responses.timeout(const Duration(seconds: 10));
        return await readExtendedList(stream, parseFavoriteDestination);
      } finally {
        await listener.cancel();
      }
    });

Future<void> navigateFavCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String id,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:navigate $id",
    isCurrent: isCurrent,
  );
  if (response != "nav:ok") {
    _log.severe(
        "Failed to navigate to favorite destination, response: $response");
    throw "Failed to navigate to favorite destination, response: $response";
  }
  return;
}

Future<void> deleteFavDestinationCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String id,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "nav:fav:delete $id",
    isCurrent: isCurrent,
  );
  if (response != "nav:ok") {
    _log.severe("Failed to delete favorite destination, response: $response");
    throw "Failed to delete favorite destination, response: $response";
  }
  return;
}
