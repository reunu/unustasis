import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/extended_response.dart';

import 'characteristic_repository.dart';
import 'command_transport.dart';

final _log = Logger('BleCommands');

class LsCapabilityGroups {
  const LsCapabilityGroups(this.versions,
      {required this.usedFallback, this.answered = true});
  final Map<String, int?> versions;
  final bool usedFallback;

  /// False when nothing answered, so the list is unknown rather than empty.
  final bool answered;
  bool contains(String group) => versions.containsKey(group);
}

Map<String, int?> _parseCapabilityGroups(String response, String command) {
  final prefix = '$command:';
  if (!response.startsWith(prefix)) {
    throw const ExtendedResponseFormatException(
        'unexpected capability-group response');
  }
  final values = response.substring(prefix.length).split(':');
  if (values.isEmpty || values.any((value) => value.isEmpty)) {
    throw const ExtendedResponseFormatException('empty capability group');
  }
  final groups = <String, int?>{};
  for (final value in values) {
    final parts = value.split('=');
    if (parts.length > 2 ||
        parts.first.isEmpty ||
        !RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(parts.first)) {
      throw const ExtendedResponseFormatException('invalid capability group');
    }
    final version = parts.length == 1 ? null : int.tryParse(parts.last);
    if (parts.length == 2 && (version == null || version < 1) ||
        groups.containsKey(parts.first)) {
      throw const ExtendedResponseFormatException(
          'invalid capability group version');
    }
    groups[parts.first] = version;
  }
  return groups;
}

/// Reads the LS 1.0 `cap:list` count header and its individual category
/// notifications under one lease, so no concurrent command can consume one.
Future<Set<String>> _readCapabilityList(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
  Duration responseTimeout = extendedResponseTimeout,
}) =>
    withExtendedChannel(() async {
      checkCommandCurrent(isCurrent);
      if (scooter == null || scooter.isDisconnected) {
        throw StateError('Scooter not connected');
      }
      final command = repo.extendedCommandCharacteristic;
      final response = repo.extendedResponseCharacteristic;
      if (command == null || response == null) {
        throw StateError('Extended command characteristics not available');
      }
      await ensureExtendedNotify(repo, response, isCurrent: isCurrent);
      checkCommandCurrent(isCurrent);
      final listener = ExtendedResponseListener(response.onValueReceived);
      var first = true;
      try {
        await sendCommand(scooter, repo, 'cap:list',
            characteristic: command, isCurrent: isCurrent);
        final messages = listener.responses.map((message) {
          repo.noteExtendedResponse();
          if (first) {
            first = false;
            if (!RegExp(r'^cap:count:[0-9]+$').hasMatch(message)) {
              throw const ExtendedResponseFormatException(
                  'invalid cap:list count');
            }
          }
          return message;
        }).timeout(responseTimeout);
        final categories = await readExtendedList<String>(messages, (message) {
          if (!RegExp(r'^cap:[a-z][a-z0-9-]*$').hasMatch(message)) {
            throw const ExtendedResponseFormatException(
                'invalid cap:list category');
          }
          return message.substring('cap:'.length);
        });
        if (categories.toSet().length != categories.length) {
          throw const ExtendedResponseFormatException(
              'duplicate cap:list category');
        }
        return categories.toSet();
      } finally {
        await listener.cancel();
      }
    });

/// Discovers all extension groups with one `cap:ext` response. On old
/// firmware `cap:list` is a counted multi-response exchange.
Future<LsCapabilityGroups> discoverLsCapabilityGroupsCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
  Duration responseTimeout = extendedResponseTimeout,
}) async {
  // A channel that was never discovered is a definite answer.
  if (repo.extendedChannelMissing) {
    return const LsCapabilityGroups({}, usedFallback: true);
  }
  var answered = false;
  try {
    final response = await sendLsExtendedCommand(scooter, repo, 'cap:ext',
        isCurrent: isCurrent, responseTimeout: responseTimeout);
    if (response != null) {
      return LsCapabilityGroups(_parseCapabilityGroups(response, 'cap:ext'),
          usedFallback: false);
    }
  } on ExtendedResponseFormatException {
    // Firmware predating cap:ext responds with an error message.
    answered = true;
  } catch (e) {
    _log.fine('cap:ext unavailable: $e');
  }
  try {
    final categories = await _readCapabilityList(scooter, repo,
        isCurrent: isCurrent, responseTimeout: responseTimeout);
    return LsCapabilityGroups(
        {for (final category in categories) category: null},
        usedFallback: true);
  } on TimeoutException {
    repo.noteSilentExtendedCommand();
  } on ExtendedResponseFormatException catch (e) {
    answered = true;
    _log.fine('cap:list unavailable: $e');
  } catch (e) {
    _log.fine('cap:list unavailable: $e');
  }
  return LsCapabilityGroups(const {}, usedFallback: true, answered: answered);
}

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
  CharacteristicRepository repo, {
  bool Function()? isCurrent,
}) =>
    getLsCapabilitiesCommand(scooter, repo, "pm", isCurrent: isCurrent);

/// Queries which commands the scooter supports in [category] ("pm", "config",
/// …). Returns an empty set on firmware that doesn't support the capability
/// query (error response or timeout).
Future<Set<String>> getLsCapabilitiesCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String category, {
  bool Function()? isCurrent,
}) =>
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

      await ensureExtendedNotify(repo, resp, isCurrent: isCurrent);
      checkCommandCurrent(isCurrent);
      final listener = ExtendedResponseListener(resp.onValueReceived);
      try {
        await sendCommand(scooter, repo, "cap:$category",
            characteristic: cmd, isCurrent: isCurrent);
        final stream = listener.responses.map((response) {
          repo.noteExtendedResponse();
          return response;
        }).timeout(extendedResponseTimeout);
        final entries = await readExtendedList(
            stream, (msg) => parseCapabilityEntry(category, msg));
        return entries.toSet();
      } on TimeoutException {
        repo.noteSilentExtendedCommand();
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
