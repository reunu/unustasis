import 'package:shared_preferences/shared_preferences.dart';

/// Bridge between the native Tasker plugin and the background service that
/// actually talks to the scooter.
///
/// The plugin's broadcast receiver (TaskerActionReceiver.kt) kicks off exactly
/// the same background-service action the home screen widget buttons use, then
/// blocks until that action reports back. SharedPreferences carries the result:
/// it's already how widget taps reach the service isolate, and the receiver
/// runs in the same process as the service, so it can watch for the result key
/// directly.
///
/// Keys are written unprefixed here; the native side reads them with the
/// `flutter.` prefix that shared_preferences adds.

/// Holds the id of the request currently in flight, when it came from Tasker.
/// Written alongside `pendingWidgetActionName`, and cleared as soon as the
/// action is picked up so a later widget tap can't inherit it.
const String taskerRequestIdKey = "pendingActionRequestId";

/// Results are stored as `actionResult.<requestId>`. The native side removes
/// each key once it has read it.
const String taskerResultPrefix = "actionResult.";

/// The scooter did what was asked and reported the new state.
const String taskerResultOk = "ok";

/// A scooter is set up, but couldn't be reached — out of range, or Bluetooth
/// is off. Worth retrying later.
const String taskerResultNotConnected = "not_connected";

/// No scooter has been added to the app at all, so there was nothing to
/// connect to. Retrying won't help until one is set up.
const String taskerResultNoScooterSaved = "no_scooter_saved";

/// Android refused to start the background service from the background. A
/// widget tap carries a short exemption that a broadcast from another app does
/// not, so this is reached when the service wasn't already running.
const String taskerResultServiceBlocked = "service_blocked";

/// Another action (a widget tap, or an earlier Tasker request) was still
/// running, so this one was dropped rather than queued.
const String taskerResultBusy = "busy";

/// The command went out, but the scooter never reported the state it should
/// have ended up in.
const String taskerResultNotConfirmed = "not_confirmed";

/// Tasker asked for something this build doesn't know how to do.
const String taskerResultUnsupportedAction = "unsupported_action";

/// Prefix for anything that threw; the exception is appended.
const String taskerResultFailedPrefix = "failed:";

/// How long an unread result sticks around. Tasker being killed mid-wait
/// leaves a key behind that nobody will ever collect, so results are swept on
/// the way past.
const Duration _resultRetention = Duration(minutes: 10);

/// Reads and clears the id of the request waiting on the next action, if the
/// trigger came from Tasker rather than a widget tap.
///
/// Cleared on read so a later widget tap can't inherit an id left behind by an
/// abandoned request, and re-read from disk because the trigger was handled in
/// a different isolate.
Future<String?> takePendingRequestId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final requestId = prefs.getString(taskerRequestIdKey);
  if (requestId != null) await prefs.remove(taskerRequestIdKey);
  return requestId;
}

/// Describes a thrown action failure in the bridge's own vocabulary.
///
/// [sendCommand] throws plain strings for a link that isn't there; they all
/// amount to the same thing for someone waiting on the action, and are worth
/// telling apart from a command that went out and then went wrong.
String taskerResultForError(Object error) {
  final message = error.toString();
  final missingLink = message.contains("Scooter not found") ||
      message.contains("Scooter disconnected") ||
      message.contains("Could not send command");
  return missingLink ? taskerResultNotConnected : "$taskerResultFailedPrefix$error";
}

/// Reports [result] to whoever is waiting on [requestId], and does nothing at
/// all when the action came from a widget tap rather than Tasker.
Future<void> reportActionResult(String? requestId, String result) async {
  if (requestId == null) return;
  await publishActionResult(requestId, result);
}

/// Records the outcome of [requestId] for the waiting native receiver.
///
/// The value is `<epochMillis>:<result>` so stale entries can be aged out
/// without a second key per request.
Future<void> publishActionResult(String requestId, String result) async {
  final prefs = await SharedPreferences.getInstance();
  // The result is read from another isolate's view of the same file, and other
  // isolates may have added result keys since this one last looked.
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
