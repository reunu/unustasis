import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/background/tasker_bridge.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('taskerResultForError', () {
    test('reports the thrown link failures as a lost connection', () {
      // The literal strings sendCommand throws in ble_commands.dart.
      expect(taskerResultForError("Scooter not found!"), taskerResultNotConnected);
      expect(taskerResultForError("Scooter disconnected!"), taskerResultNotConnected);
      expect(
        taskerResultForError("Could not send command, move closer or reconnect"),
        taskerResultNotConnected,
      );
    });

    test('passes anything else through with its message', () {
      expect(
        taskerResultForError(StateError("characteristic write failed")),
        startsWith(taskerResultFailedPrefix),
      );
      expect(taskerResultForError("boom"), contains("boom"));
    });
  });

  group('reportActionResult', () {
    test('stays silent for a widget tap, which has no request id', () async {
      await reportActionResult(null, taskerResultOk);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith(taskerResultPrefix)), isEmpty);
    });
  });

  group('takePendingRequestId', () {
    test('returns the id once, then clears it', () async {
      SharedPreferences.setMockInitialValues({taskerRequestIdKey: "abc-123"});

      expect(await takePendingRequestId(), "abc-123");
      // A later widget tap must not inherit it.
      expect(await takePendingRequestId(), isNull);
    });

    test('returns null when the trigger was a widget tap', () async {
      expect(await takePendingRequestId(), isNull);
    });
  });

  group('publishActionResult', () {
    test('stores the result under the request id, stamped with the time', () async {
      await publishActionResult("abc-123", taskerResultOk);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString("${taskerResultPrefix}abc-123");

      expect(stored, isNotNull);
      // The native side splits on the first colon, so the stamp has to come
      // first and the result has to survive intact after it.
      final stamp = int.parse(stored!.split(":").first);
      expect(stored.substring(stored.indexOf(":") + 1), taskerResultOk);
      expect(
        (DateTime.now().millisecondsSinceEpoch - stamp).abs(),
        lessThan(const Duration(minutes: 1).inMilliseconds),
      );
    });

    test('keeps results that contain colons readable', () async {
      await publishActionResult("abc-123", "${taskerResultFailedPrefix}Scooter not found!");

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString("${taskerResultPrefix}abc-123")!;

      expect(
        stored.substring(stored.indexOf(":") + 1),
        "${taskerResultFailedPrefix}Scooter not found!",
      );
    });

    test('sweeps results nobody collected, but leaves fresh ones alone', () async {
      final long = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final recent = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        "${taskerResultPrefix}stale": "$long:$taskerResultOk",
        "${taskerResultPrefix}fresh": "$recent:$taskerResultOk",
        "${taskerResultPrefix}corrupt": "not-a-timestamp",
        "pendingWidgetActionName": "unlock",
      });

      await publishActionResult("new", taskerResultNotConnected);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString("${taskerResultPrefix}stale"), isNull);
      expect(prefs.getString("${taskerResultPrefix}corrupt"), isNull);
      expect(prefs.getString("${taskerResultPrefix}fresh"), isNotNull);
      expect(prefs.getString("${taskerResultPrefix}new"), isNotNull);
      // Sweeping must not touch the keys the widget handover uses.
      expect(prefs.getString("pendingWidgetActionName"), "unlock");
    });
  });
}
