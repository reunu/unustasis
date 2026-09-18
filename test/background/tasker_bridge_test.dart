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

  group('pending action queue', () {
    test('hands each action back with the id that was queued with it', () async {
      await queuePendingAction(PendingAction("unlock", requestId: "abc-123"));
      await queuePendingAction(PendingAction("lock", requestId: "def-456"));

      final taken = await takePendingActions();

      // The second trigger must not have overwritten the first, and neither
      // id may end up on the other's action.
      expect(taken.map((e) => e.action), ["unlock", "lock"]);
      expect(taken.map((e) => e.requestId), ["abc-123", "def-456"]);
    });

    test('empties the queue in one read, so nothing is run twice', () async {
      await queuePendingAction(PendingAction("unlock", requestId: "abc-123"));

      expect(await takePendingActions(), hasLength(1));
      expect(await takePendingActions(), isEmpty);
    });

    test('carries no id for a widget tap', () async {
      await queuePendingAction(PendingAction("unlock"));

      final taken = await takePendingActions();
      expect(taken.single.requestId, isNull);
    });

    test('a widget tap does not inherit an abandoned request id', () async {
      await queuePendingAction(PendingAction("lock", requestId: "abc-123"));
      await takePendingActions();

      await queuePendingAction(PendingAction("unlock"));
      expect((await takePendingActions()).single.requestId, isNull);
    });

    test('drops entries nobody picked up in time', () async {
      await queuePendingAction(PendingAction(
        "unlock",
        requestId: "stale",
        queuedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ));
      await queuePendingAction(PendingAction(
        "lock",
        requestId: "fresh",
        queuedAt: DateTime.now(),
      ));

      final taken = await takePendingActions();
      expect(taken.map((e) => e.requestId), ["fresh"]);
    });

    test('hasPendingActions peeks without consuming', () async {
      await queuePendingAction(PendingAction("unlock", requestId: "abc-123"));

      expect(await hasPendingActions(), isTrue);
      expect(await takePendingActions(), hasLength(1));
      expect(await hasPendingActions(), isFalse);
    });

    test('dropPendingAction removes only the matching entry', () async {
      await queuePendingAction(PendingAction("unlock", requestId: "abc-123"));
      await queuePendingAction(PendingAction("lock", requestId: "def-456"));

      await dropPendingAction(PendingAction("unlock", requestId: "abc-123"));

      final taken = await takePendingActions();
      expect(taken.map((e) => e.requestId), ["def-456"]);
    });

    test('dropPendingAction clears the queue when it empties', () async {
      await queuePendingAction(PendingAction("unlock", requestId: "abc-123"));

      await dropPendingAction(PendingAction("unlock", requestId: "abc-123"));

      expect(await hasPendingActions(), isFalse);
      expect(await takePendingActions(), isEmpty);
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
