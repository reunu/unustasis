import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// Librescoot settings key holding the APN the modem attaches with. An empty
/// value means the modem falls back to the SIM operator's defaults.
const String lsKeyCellularApn = "cellular.apn";

/// Librescoot settings key that keeps the running battery active while the
/// seatbox is open, instead of letting it drop out. battery-service also wakes
/// a sleeping pack when this is on, which is what makes it useful for digging
/// a scooter out of a flat AUX battery.
const String lsKeyBatteryKeepActiveOnSeatboxOpen = "scooter.battery-keep-active-on-seatbox-open";

Future<void> _extendedChannelQueue = Future.value();

/// Serializes access to the extended command/response characteristics so that
/// concurrent callers can't consume each other's responses or toggle the
/// notify state underneath each other.
Future<T> _withExtendedChannel<T>(Future<T> Function() action) {
  final result = _extendedChannelQueue.then((_) => action());
  _extendedChannelQueue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Thrown when the scooter's reply to an extended command doesn't have the
/// shape we expect, so an error reply can be told apart from a valid one.
class ExtendedResponseFormatException implements Exception {
  final String message;
  const ExtendedResponseFormatException(this.message);

  @override
  String toString() => "ExtendedResponseFormatException: $message";
}

/// Buffers the extended response characteristic's notifications.
///
/// `onValueReceived` is a broadcast stream, so anything emitted while nobody
/// is subscribed is dropped. Constructing this before writing the command
/// closes the window between the write and the read: responses that land in
/// it are queued on a single-subscription controller and delivered as soon as
/// the caller starts reading, instead of being lost to a 10 second timeout.
@visibleForTesting
class ExtendedResponseListener {
  final StreamController<String> _buffer = StreamController<String>();
  late final StreamSubscription<List<int>> _subscription;

  ExtendedResponseListener(Stream<List<int>> source) {
    _subscription = source.listen(
      (value) {
        if (value.isEmpty || _buffer.isClosed) return;
        // The protocol is ASCII, but user-supplied content (a destination name
        // set from another app, say) arrives as UTF-8. UTF-8 is a superset of
        // ASCII, and allowMalformed keeps one bad byte from killing the whole
        // response, which used to throw and take the subscription with it.
        _buffer.add(utf8.decode(value, allowMalformed: true).replaceAll('\x00', ''));
      },
      onError: (Object e, StackTrace s) {
        if (!_buffer.isClosed) _buffer.addError(e, s);
      },
    );
  }

  /// Decoded responses, oldest first.
  Stream<String> get responses => _buffer.stream;

  Future<void> cancel() async {
    await _subscription.cancel();
    // Deliberately not awaited: closing a single-subscription controller that
    // was never listened to (e.g. the command write threw) never completes.
    if (!_buffer.isClosed) unawaited(_buffer.close());
  }
}

/// Reads a counted list from an extended response [stream].
///
/// Expects the first message to carry the count as its last colon-separated
/// segment (e.g. `keycard:count:3`), followed by that many entry messages.
/// [parseEntry] converts each entry message to [T]; returning null skips it.
///
/// Throws [ExtendedResponseFormatException] when the first message carries no
/// parseable count, so an error reply can't pass itself off as an empty list.
@visibleForTesting
Future<List<T>> readExtendedList<T>(
  Stream<String> stream,
  T? Function(String msg) parseEntry,
) async {
  final List<T> results = [];
  int? count;
  await for (final msg in stream) {
    if (count == null) {
      final parsed = int.tryParse(msg.split(':').last);
      if (parsed == null) {
        throw ExtendedResponseFormatException("expected a count, got '$msg'");
      }
      count = parsed;
      if (count == 0) break;
    } else {
      final entry = parseEntry(msg);
      if (entry != null) results.add(entry);
      if (results.length >= count) break;
    }
  }
  return results;
}

/// Turns notifications on for the extended response characteristic unless
/// they're already on.
///
/// `isNotifying` is derived from the cached CCCD value, which flutter_blue_plus
/// clears on disconnect, so the subscription lives for exactly one connection.
/// Toggling it per command cost two extra CCCD writes each time and dropped
/// any response that arrived while notify was off.
Future<void> _ensureExtendedNotify(BluetoothCharacteristic resp) async {
  if (resp.isNotifying) return;
  await resp.setNotifyValue(true);
}

// Maximum payload for the extended command characteristic. The basic command
// characteristic is limited to 20 bytes (default BLE MTU minus ATT overhead),
// but the extended characteristic uses allowLongWrite so it can carry more.
// Keep this well under typical negotiated MTUs (185–512 bytes) and the
// scooter's own command-buffer size.
const int _extendedCommandMaxBytes = 100;

/// Writes an ASCII command to the scooter's BLE command characteristic.
Future<void> sendCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository characteristicRepository,
  String command, {
  BluetoothCharacteristic? characteristic,
  bool allowLongWrite = false,
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

  await target.write(ascii.encode(command), allowLongWrite: allowLongWrite);
}

/// Returns [name] truncated so that [prefix] + "," + name fits within
/// [_extendedCommandMaxBytes]. Returns null when there is no room at all.
String? _truncateNavName(String prefix, String? name) {
  if (name == null || name.isEmpty) return null;
  final available = _extendedCommandMaxBytes - prefix.length - 1; // -1 for ","
  if (available <= 0) return null;
  return name.length > available ? name.substring(0, available) : name;
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

  await _ensureExtendedNotify(resp);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, command, characteristic: cmd, allowLongWrite: true);
    return await listener.responses.first.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    log.warning("sendLsExtendedCommand: timeout waiting for response to '$command'");
    return null;
  } finally {
    await listener.cancel();
  }
}

/// Queries the installed OS version of [component] ("mdb" or "dbc") via the
/// extended channel (`status:version:<component>`). Returns the raw version
/// string — "unknown" when the scooter has no record (e.g. the dashboard
/// never booted) — or null on timeout, unexpected replies, or firmware that
/// predates the command.
Future<String?> getInstalledVersionCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String component,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "status:version:$component");
  if (response == null) return null;
  final prefix = "status:version:$component:";
  if (!response.startsWith(prefix)) {
    log.warning("Unexpected version response for $component: $response");
    return null;
  }
  return response.substring(prefix.length);
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
  final base = "nav:dest ${destination.location.latitude},${destination.location.longitude}";
  final name = _truncateNavName(base, destination.name);
  final command = name != null ? "$base,$name" : base;
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    command,
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
  final base = "nav:fav:add ${destination.location.latitude},${destination.location.longitude}";
  final name = _truncateNavName(base, destination.name) ?? destination.name!;
  final response = await sendLsExtendedCommand(
    scooter,
    repo,
    "$base,$name",
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

  await _ensureExtendedNotify(resp);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, "nav:fav:list", characteristic: cmd);
    final stream = listener.responses.timeout(const Duration(seconds: 10));
    return await readExtendedList(stream, (msg) {
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
    await listener.cancel();
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
/// Expects: `keycard:count:<n>`, then one `keycard:card:<uid>` message per entry.
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

  await _ensureExtendedNotify(resp);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, "keycard:list", characteristic: cmd);
    final stream = listener.responses.timeout(const Duration(seconds: 10));
    return await readExtendedList(stream, (msg) {
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
    await listener.cancel();
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

/// Why a user-entered APN can't be sent to the scooter.
enum ApnProblem { empty, invalidCharacters, tooLong }

const String _apnCommandPrefix = "config:apn ";

/// Longest APN that still fits into a single extended command.
const int maxApnLength = _extendedCommandMaxBytes - _apnCommandPrefix.length;

// APNs are DNS-style labels, so anything outside printable ASCII (a space
// included) would be rejected by the modem anyway, and the command
// characteristic only carries ASCII.
final RegExp _apnAllowedChars = RegExp(r'^[\x21-\x7E]+$');

/// Checks an already-trimmed APN against what the command channel and the
/// modem accept. Returns null when [apn] is usable.
ApnProblem? checkApn(String apn) {
  if (apn.isEmpty) return ApnProblem.empty;
  if (!_apnAllowedChars.hasMatch(apn)) return ApnProblem.invalidCharacters;
  if (apn.length > maxApnLength) return ApnProblem.tooLong;
  return null;
}

/// Sets the APN the scooter's modem attaches with.
///
/// Surrounding whitespace is trimmed. An empty APN is rejected here rather than
/// sent on, so that emptying the text field cannot silently drop the scooter
/// onto operator defaults. Use [clearCellularApnCommand] to do that on purpose.
Future<void> setCellularApnCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
  String apn,
) async {
  final trimmed = apn.trim();
  final problem = checkApn(trimmed);
  if (problem != null) {
    log.warning("Refusing to send APN '$apn': ${problem.name}");
    throw "Invalid APN (${problem.name})";
  }
  final response = await sendLsExtendedCommand(scooter, repo, "$_apnCommandPrefix$trimmed");
  if (response != "config:ok") {
    log.severe("Failed to set APN, response: $response");
    throw "Failed to set APN, response: $response";
  }
  return;
}

/// Clears the configured APN so the modem falls back to whatever the SIM
/// operator hands out.
///
/// Sends the prefix and nothing after it. The trailing space in
/// [_apnCommandPrefix] is load-bearing: the firmware splits the payload on the
/// first space and answers `config:error:missing value` when there is no second
/// field, so `config:apn ` sets an empty value where `config:apn` would fail.
/// Only the value gets trimmed on the way in, never the command.
Future<void> clearCellularApnCommand(
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, _apnCommandPrefix);
  if (response != "config:ok") {
    log.severe("Failed to clear APN, response: $response");
    throw "Failed to clear APN, response: $response";
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

/// Pulls the command name out of one `cap:<category>:<command>[ <args>]` entry.
///
/// The count header is consumed by [readExtendedList] before this sees
/// anything, so every message reaching here should be an entry. Returns null
/// for one that isn't for [category], which [readExtendedList] then skips.
@visibleForTesting
String? parseCapabilityEntry(String category, String msg) {
  final prefix = "cap:$category:";
  if (!msg.startsWith(prefix)) return null;
  final name = msg.substring(prefix.length).split(" ").first;
  return name.isNotEmpty ? name : null;
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
    _withExtendedChannel(() async {
  if (scooter == null || scooter.isDisconnected) {
    throw "Scooter not connected!";
  }
  final cmd = repo.extendedCommandCharacteristic;
  final resp = repo.extendedResponseCharacteristic;
  if (cmd == null || resp == null) {
    throw "Extended command characteristics not available";
  }

  await _ensureExtendedNotify(resp);
  final listener = ExtendedResponseListener(resp.onValueReceived);
  try {
    await sendCommand(scooter, repo, "cap:$category", characteristic: cmd);
    final stream = listener.responses.timeout(const Duration(seconds: 10));
    final entries = await readExtendedList(stream, (msg) => parseCapabilityEntry(category, msg));
    return entries.toSet();
  } on TimeoutException {
    log.info("getLsCapabilitiesCommand: timeout, assuming no $category capabilities");
    return <String>{};
  } on ExtendedResponseFormatException catch (e) {
    // Firmware without the capability query answers with an error string
    // rather than a count. Treat that as "no capabilities", but log it.
    log.info("getLsCapabilitiesCommand: unparseable reply, assuming no $category capabilities ($e)");
    return <String>{};
  } finally {
    await listener.cancel();
  }
});

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
  BluetoothDevice? scooter,
  CharacteristicRepository repo,
) async {
  final response = await sendLsExtendedCommand(scooter, repo, "ble:forget");
  if (response != "ble:forget:ok") {
    log.warning("Scooter would not forget this phone, response: $response");
    throw "Failed to forget the scooter side of the bond, response: $response";
  }
}

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
