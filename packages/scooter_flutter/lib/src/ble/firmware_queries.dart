import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/extended_response.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';

final _log = Logger('BleCommands');

/// Queries the installed OS version of [component] ("mdb" or "dbc") via the
/// extended channel (`status:version:<component>`). Returns the raw version
/// string — "unknown" when the scooter has no record (e.g. the dashboard
/// never booted) — or null on timeout, unexpected replies, or firmware that
/// predates the command.
Future<String?> getInstalledVersionCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String component, {
  bool Function()? isCurrent,
}) async {
  final response = await sendLsExtendedCommand(
      scooter, repo, "status:version:$component",
      isCurrent: isCurrent);
  if (response == null) return null;
  final prefix = "status:version:$component:";
  if (!response.startsWith(prefix)) {
    _log.warning("Unexpected version response for $component: $response");
    return null;
  }
  return response.substring(prefix.length);
}

/// Queries the scooter's power-management capabilities (e.g. "hibernate-for",
/// "hibernate-cancel").
Future<Set<String>> getPmCapabilitiesCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) =>
    getLsCapabilitiesCommand(scooter, repo, "pm");

/// Queries which commands the scooter supports in [category] ("pm", "config",
/// …). Returns an empty set on firmware that doesn't support the capability
/// query (error response or timeout).
Future<Set<String>> getLsCapabilitiesCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String category,
) =>
    withExtendedChannel(() async {
      if (scooter == null || scooter.isDisconnected) {
        throw "Scooter not connected!";
      }
      final cmd = repo.extendedCommandCharacteristic;
      final resp = repo.extendedResponseCharacteristic;
      if (cmd == null || resp == null) {
        throw "Extended command characteristics not available";
      }

      await ensureExtendedNotify(resp);
      final listener = ExtendedResponseListener(resp.onValueReceived);
      try {
        await sendCommand(scooter, repo, "cap:$category", characteristic: cmd);
        final stream = listener.responses.timeout(const Duration(seconds: 10));
        final entries = await readExtendedList(
            stream, (msg) => parseCapabilityEntry(category, msg));
        return entries.toSet();
      } on TimeoutException {
        _log.info(
            "getLsCapabilitiesCommand: timeout, assuming no $category capabilities");
        return <String>{};
      } on ExtendedResponseFormatException catch (e) {
        // Firmware without the capability query answers with an error string
        // rather than a count. Treat that as "no capabilities", but log it.
        _log.info(
            "getLsCapabilitiesCommand: unparseable reply, assuming no $category capabilities ($e)");
        return <String>{};
      } finally {
        await listener.cancel();
      }
    });

/// Reads a librescoot settings key via the generic get command. Returns null
/// if the key or the get command itself is unsupported (or on timeout), and
/// "" if the key exists but is unset.
Future<String?> getLsSettingCommand(
    BluetoothDevice? scooter, CharacteristicRepository repo, String key,
    {bool Function()? isCurrent}) async {
  final response = await sendLsExtendedCommand(scooter, repo, "get:$key",
      isCurrent: isCurrent);
  final prefix = "get:$key:";
  if (response == null || !response.startsWith(prefix)) {
    // covers "get:error:unknown key", "error:unknown command" and timeouts
    _log.info(
        "getLsSettingCommand: '$key' unsupported or failed, response: $response");
    return null;
  }
  // the value is everything after the first colon following the key; it may
  // itself contain spaces or colons (e.g. cron expressions)
  return response.substring(prefix.length);
}

/// Writes a librescoot settings key. [value] must not be empty (the firmware
/// rejects empty values).
Future<void> setLsSettingCommand(BluetoothDevice? scooter,
    CharacteristicRepository repo, String key, String value,
    {bool Function()? isCurrent}) async {
  if (value.isEmpty) {
    throw "Setting value must not be empty";
  }
  final response = await sendLsExtendedCommand(scooter, repo, "set:$key:$value",
      isCurrent: isCurrent);
  if (response != "set:ok:$key") {
    _log.severe("Failed to set $key, response: $response");
    throw "Failed to set $key, response: $response";
  }
}
