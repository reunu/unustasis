import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bridge between the native Tasker plugin and the background service.
///
/// The plugin's receiver runs the same action a widget button does, then blocks
/// until it reports back. SharedPreferences carries the result: it's already
/// how widget taps reach the service isolate, and the receiver shares the
/// process, so it can watch the result key directly. Keys are written
/// unprefixed here; the native side reads them with shared_preferences'
/// `flutter.` prefix.

/// Queue of actions handed to the service, each with the Tasker request
/// waiting on it. A queue rather than a single slot: two triggers can land
/// before the service reads either, and the second would overwrite the first,
/// leaving its caller waiting for an answer sent under someone else's id.
const String pendingActionQueueKey = "pendingWidgetActionQueue";

/// Results are stored as `actionResult.<requestId>`, cleared once read.
const String taskerResultPrefix = "actionResult.";

/// The scooter did what was asked and reported the new state.
const String taskerResultOk = "ok";

/// A scooter is set up but couldn't be reached. Worth retrying later.
const String taskerResultNotConnected = "not_connected";

/// No scooter has been added to the app, so there was nothing to connect to.
const String taskerResultNoScooterSaved = "no_scooter_saved";

/// Android refused to start the background service from the background, which
/// only happens when the service wasn't already running.
const String taskerResultServiceBlocked = "service_blocked";

/// Another action was still running, so this one was dropped rather than
/// queued.
const String taskerResultBusy = "busy";

/// The command went out, but the scooter never reported the expected state.
const String taskerResultNotConfirmed = "not_confirmed";

/// Tasker asked for something this build doesn't know how to do.
const String taskerResultUnsupportedAction = "unsupported_action";

/// Prefix for anything that threw; the exception is appended.
const String taskerResultFailedPrefix = "failed:";

/// How long a result nobody collected sticks around before being swept.
const Duration _resultRetention = Duration(minutes: 10);

/// How long a queued action is still worth running. Tasker has long given up
/// by then, so anything older would move the scooter with nobody expecting it.
const Duration _queueRetention = Duration(minutes: 5);

/// One action waiting for the service. [requestId] is set only for Tasker,
/// which is blocking on the outcome; a widget tap leaves it null.
class PendingAction {
  PendingAction(this.action, {this.requestId, DateTime? queuedAt})
      : queuedAt = queuedAt ?? DateTime.now();

  final String action;
  final String? requestId;
  final DateTime queuedAt;

  bool get isStale => DateTime.now().difference(queuedAt) > _queueRetention;

  String encode() => jsonEncode({
        "action": action,
        "requestId": requestId,
        "queuedAt": queuedAt.millisecondsSinceEpoch,
      });

  static PendingAction? decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map || json["action"] is! String) return null;
    return PendingAction(
      json["action"] as String,
      requestId: json["requestId"] as String?,
      queuedAt: DateTime.fromMillisecondsSinceEpoch(json["queuedAt"] as int? ?? 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAction && other.action == action && other.requestId == requestId;

  @override
  int get hashCode => Object.hash(action, requestId);

  @override
  String toString() => requestId == null ? action : "$action($requestId)";
}

/// Re-read from disk every time: the queue is written in the callback isolate
/// and drained in the service isolate.
Future<List<PendingAction>> _read(SharedPreferences prefs) async {
  await prefs.reload();
  final raw = prefs.getStringList(pendingActionQueueKey) ?? const <String>[];
  return raw
      .map((entry) {
        try {
          return PendingAction.decode(entry);
        } catch (_) {
          return null; // half-written or from an older build
        }
      })
      .whereType<PendingAction>()
      .where((entry) => !entry.isStale)
      .toList();
}

Future<void> _write(SharedPreferences prefs, List<PendingAction> entries) =>
    entries.isEmpty
        ? prefs.remove(pendingActionQueueKey)
        : prefs.setStringList(pendingActionQueueKey, [for (final e in entries) e.encode()]);

/// Adds [entry] for the service to pick up.
Future<void> queuePendingAction(PendingAction entry) async {
  final prefs = await SharedPreferences.getInstance();
  final entries = await _read(prefs);
  await _write(prefs, entries..add(entry));
}

/// Whether anything is waiting, without consuming it.
Future<bool> hasPendingActions() async =>
    (await _read(await SharedPreferences.getInstance())).isNotEmpty;

/// Takes the whole queue in one go, so a trigger and the fallback sweep can't
/// come away with the same entry.
Future<List<PendingAction>> takePendingActions() async {
  final prefs = await SharedPreferences.getInstance();
  final entries = await _read(prefs);
  await prefs.remove(pendingActionQueueKey);
  return entries;
}

/// Takes back what a trigger queued once it's clear nothing will run it. Only
/// the first match goes, so an identical action queued meanwhile stays.
Future<void> dropPendingAction(PendingAction entry) async {
  final prefs = await SharedPreferences.getInstance();
  final entries = await _read(prefs);
  if (entries.remove(entry)) await _write(prefs, entries);
}

/// Describes a thrown failure in the bridge's own vocabulary. `sendCommand`
/// throws plain strings when the link isn't there, which is worth telling
/// apart from a command that went out and then went wrong.
String taskerResultForError(Object error) {
  final message = error.toString();
  final missingLink = message.contains("Scooter not found") ||
      message.contains("Scooter disconnected") ||
      message.contains("Could not send command");
  return missingLink ? taskerResultNotConnected : "$taskerResultFailedPrefix$error";
}

/// Reports [result] to whoever is waiting, and does nothing for a widget tap.
Future<void> reportActionResult(String? requestId, String result) async {
  if (requestId == null) return;
  await publishActionResult(requestId, result);
}

/// Records the outcome for the waiting native receiver, as
/// `<epochMillis>:<result>` so stale entries can be aged out.
Future<void> publishActionResult(String requestId, String result) async {
  final prefs = await SharedPreferences.getInstance();
  // Other isolates may have added result keys since this one last looked.
  await prefs.reload();
  final now = DateTime.now().millisecondsSinceEpoch;
  final key = "$taskerResultPrefix$requestId";
  await prefs.setString(key, "$now:$result");

  for (final staleCandidate in prefs.getKeys().toList()) {
    if (staleCandidate == key || !staleCandidate.startsWith(taskerResultPrefix)) {
      continue;
    }
    final written = int.tryParse(prefs.getString(staleCandidate)?.split(":").first ?? "");
    if (written == null || now - written > _resultRetention.inMilliseconds) {
      await prefs.remove(staleCandidate);
    }
  }
}
