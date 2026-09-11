import 'package:shared_preferences/shared_preferences.dart';

/// Bridge between the native Tasker plugin and the background service.
///
/// The plugin's receiver runs the same action a widget button does, then blocks
/// until it reports back. SharedPreferences carries the result: it's already
/// how widget taps reach the service isolate, and the receiver shares the
/// process, so it can watch the result key directly. Keys are written
/// unprefixed here; the native side reads them with shared_preferences'
/// `flutter.` prefix.

/// Id of the request in flight, when it came from Tasker rather than a widget.
const String taskerRequestIdKey = "pendingActionRequestId";

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

/// Reads and clears the id of the request waiting on the next action.
///
/// Cleared on read so a later widget tap can't inherit an abandoned id, and
/// re-read from disk because the trigger was handled in another isolate.
Future<String?> takePendingRequestId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final requestId = prefs.getString(taskerRequestIdKey);
  if (requestId != null) await prefs.remove(taskerRequestIdKey);
  return requestId;
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
