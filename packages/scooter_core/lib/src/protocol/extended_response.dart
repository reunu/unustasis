import 'dart:async';
import 'dart:convert';

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

/// Pulls the command name out of one `cap:<category>:<command>[ <args>]` entry.
///
/// The count header is consumed by [readExtendedList] before this sees
/// anything, so every message reaching here should be an entry. Returns null
/// for one that isn't for [category], which [readExtendedList] then skips.
String? parseCapabilityEntry(String category, String msg) {
  final prefix = "cap:$category:";
  if (!msg.startsWith(prefix)) return null;
  final name = msg.substring(prefix.length).split(" ").first;
  return name.isNotEmpty ? name : null;
}
