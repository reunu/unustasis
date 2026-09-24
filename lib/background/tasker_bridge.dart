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

/// Each request has its own key, so concurrent callback isolates never
/// overwrite one another's pending actions.
const String pendingTaskerActionPrefix = 'pendingTaskerAction.';

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

/// An action waited too long to begin and was not issued.
const String taskerResultTimeout = "timeout";

/// Tasker asked for something this build doesn't know how to do.
const String taskerResultUnsupportedAction = "unsupported_action";

/// Prefix for anything that threw; the exception is appended.
const String taskerResultFailedPrefix = "failed:";

/// How long a result nobody collected sticks around before being swept.
const Duration _resultRetention = Duration(minutes: 10);

/// How long a queued action is still worth running. Tasker has long given up
/// by then, so anything older would move the scooter with nobody expecting it.
const Duration _queueRetention = Duration(seconds: 90);

/// One Tasker action waiting for the service.
class PendingAction {
  PendingAction(this.action, {required this.requestId, DateTime? queuedAt})
      : queuedAt = queuedAt ?? DateTime.now();

  final String action;
  final String requestId;
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
      requestId: json["requestId"] as String,
      queuedAt: DateTime.fromMillisecondsSinceEpoch(json["queuedAt"] as int? ?? 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAction && other.action == action && other.requestId == requestId;

  @override
  int get hashCode => Object.hash(action, requestId);

  @override
  String toString() => '$action($requestId)';
}

String _pendingKey(String id) => '$pendingTaskerActionPrefix$id';

/// Adds [entry] for the service to pick up.
Future<void> queuePendingAction(PendingAction entry) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await prefs.setString(_pendingKey(entry.requestId), entry.encode())) {
    throw StateError('Tasker action could not be persisted');
  }
}

/// Whether anything is waiting, without consuming it.
Future<bool> hasPendingActions() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getKeys().any((key) => key.startsWith(pendingTaskerActionPrefix));
}

/// Claim each request by its own key. A concurrent producer can add a distinct
/// key without losing either action.
Future<List<PendingAction>> takePendingActions() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final keys = prefs.getKeys().where((key) => key.startsWith(pendingTaskerActionPrefix)).toList()..sort();
  final entries = <PendingAction>[];
  for (final key in keys) {
    final raw = prefs.getString(key);
    if (!await prefs.remove(key)) throw StateError('Tasker action could not be claimed');
    try {
      final entry = raw == null ? null : PendingAction.decode(raw);
      if (entry != null && !entry.isStale && key == _pendingKey(entry.requestId)) entries.add(entry);
    } catch (_) {
      // Ignore malformed entries, but never run them.
    }
  }
  entries.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
  return entries;
}

Future<void> dropPendingAction(PendingAction entry) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final key = _pendingKey(entry.requestId);
  if (prefs.getString(key) != null) await prefs.remove(key);
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
