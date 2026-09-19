import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/server_notifications.dart';

void main() {
  group('parseDurationDays', () {
    test('accepts whole numbers and JSON doubles', () {
      expect(parseDurationDays(30), 30);
      expect(parseDurationDays(30.0), 30);
      expect(parseDurationDays(0), 0);
    });

    test('rejects missing, malformed and negative values', () {
      expect(parseDurationDays(null), isNull);
      expect(parseDurationDays("30"), isNull);
      expect(parseDurationDays(-1), isNull);
      expect(parseDurationDays(double.nan), isNull);
      expect(parseDurationDays(double.infinity), isNull);
    });
  });

  group('maxShowsOf', () {
    test('defaults to showing once', () {
      expect(maxShowsOf(null), 1);
      expect(maxShowsOf("3"), 1);
      expect(maxShowsOf(0), 1);
      expect(maxShowsOf(-2), 1);
    });

    test('accepts a positive count', () {
      expect(maxShowsOf(3), 3);
      expect(maxShowsOf(3.0), 3);
    });
  });

  group('isWithinWindow', () {
    final start = DateTime.utc(2026, 9, 18, 22);

    test('is inclusive on both ends', () {
      expect(isWithinWindow(start: start, durationDays: 30, now: start), isTrue);
      expect(isWithinWindow(start: start, durationDays: 30, now: start.add(const Duration(days: 30))), isTrue);
    });

    test('is false before the start and after the end', () {
      expect(isWithinWindow(start: start, durationDays: 30, now: start.subtract(const Duration(seconds: 1))), isFalse);
      expect(
        isWithinWindow(
          start: start,
          durationDays: 30,
          now: start.add(const Duration(days: 30, seconds: 1)),
        ),
        isFalse,
      );
    });

    test('compares local and UTC timestamps correctly', () {
      final localNow = start.toLocal();
      expect(isWithinWindow(start: start, durationDays: 1, now: localNow), isTrue);
    });
  });

  group('matchBuildNumber', () {
    BuildScopeMatch match({Object? exact, Object? min, Object? max, int? buildNumber = 46}) => matchBuildNumber(
          exact: exact,
          min: min,
          max: max,
          buildNumber: buildNumber,
        );

    test('an entry without a scope matches every build', () {
      expect(match(), BuildScopeMatch.match);
      expect(match(buildNumber: null), BuildScopeMatch.match);
    });

    test('matches an exact build number or a list of them', () {
      expect(match(exact: 46), BuildScopeMatch.match);
      expect(match(exact: 45), BuildScopeMatch.mismatch);
      expect(match(exact: [46, 47]), BuildScopeMatch.match);
      expect(match(exact: [44, 45]), BuildScopeMatch.mismatch);
      expect(match(exact: 46.0), BuildScopeMatch.match);
      // an empty list is the same as no constraint
      expect(match(exact: <int>[]), BuildScopeMatch.match);
    });

    test('matches min and max bounds inclusively', () {
      expect(match(min: 40), BuildScopeMatch.match);
      expect(match(min: 47), BuildScopeMatch.mismatch);
      expect(match(max: 50), BuildScopeMatch.match);
      expect(match(max: 45), BuildScopeMatch.mismatch);
      expect(match(min: 40, max: 50), BuildScopeMatch.match);
      expect(match(min: 40, max: 45), BuildScopeMatch.mismatch);
    });

    test('scopes are combined (all must match)', () {
      expect(match(exact: 46, min: 40, max: 50), BuildScopeMatch.match);
      expect(match(exact: 46, min: 47), BuildScopeMatch.mismatch);
      expect(match(exact: 46, max: 45), BuildScopeMatch.mismatch);
    });

    test('a scope that cannot be evaluated is malformed, never unscoped', () {
      const scope = BuildScopeMatch.malformed;
      expect(match(exact: "46"), scope);
      expect(match(exact: true), scope);
      expect(match(exact: [46, "47"]), scope);
      expect(match(min: "40"), scope);
      expect(match(max: null, min: {}), scope);
      // unknown app build number with a configured scope
      expect(match(exact: 46, buildNumber: null), scope);
      expect(match(min: 40, buildNumber: null), scope);
    });
  });

  group('decodeNotificationState', () {
    test('returns an empty map for missing or unreadable data', () {
      expect(decodeNotificationState(null), isEmpty);
      expect(decodeNotificationState(""), isEmpty);
      expect(decodeNotificationState("{not json"), isEmpty);
      expect(decodeNotificationState("[1, 2]"), isEmpty);
    });

    test('round-trips state', () {
      final state = {
        "go-stable-ios": const ServerNotificationState(count: 2),
        "snoozed": ServerNotificationState(count: 1, snoozedUntil: DateTime.utc(2026, 10, 1, 12)),
        "ended": const ServerNotificationState(count: 3, done: true),
      };
      expect(decodeNotificationState(encodeNotificationState(state)), state);
    });

    test('reads the earlier bare-count shape', () {
      final decoded = decodeNotificationState('{"go-stable-ios": 2}');
      expect(decoded["go-stable-ios"]!.count, 2);
      expect(decoded["go-stable-ios"]!.done, isFalse);
      expect(decoded["go-stable-ios"]!.snoozedUntil, isNull);
    });

    test('keeps usable entries and drops unusable ones', () {
      final decoded = decodeNotificationState(
          '{"good": {"count": 2}, "bad-count": {"count": "2"}, "negative": -1, "not-a-map": "x", '
          '"bad-date": {"snoozed-until": "yesterday"}, "lost-date": {"snoozed-until": null}}');
      expect(decoded.keys, ["good", "lost-date"]);
      expect(decoded["good"]!.count, 2);
      expect(decoded["lost-date"]!.snoozedUntil, isNull);
    });

    test('does not throw on a partially corrupt map', () {
      expect(() => decodeNotificationState('{"good": {"count": 1}, "bad": 1.5}'), returnsNormally);
    });
  });

  group('isEligible', () {
    final now = DateTime.utc(2026, 9, 19, 12);

    test('is true for a fresh entry', () {
      expect(isEligible(state: ServerNotificationState.initial, maxShows: 1, now: now), isTrue);
    });

    test('is false once the user ended the entry', () {
      expect(isEligible(state: const ServerNotificationState(done: true), maxShows: 9, now: now), isFalse);
    });

    test('is false once max-shows is used up', () {
      expect(isEligible(state: const ServerNotificationState(count: 1), maxShows: 1, now: now), isFalse);
      expect(isEligible(state: const ServerNotificationState(count: 3), maxShows: 3, now: now), isFalse);
      expect(isEligible(state: const ServerNotificationState(count: 2), maxShows: 3, now: now), isTrue);
    });

    test('is false until a snooze expires, and stops counting shows', () {
      final snoozed = ServerNotificationState(snoozedUntil: now.add(const Duration(days: 1)));
      expect(isEligible(state: snoozed, maxShows: 1, now: now), isFalse);
      expect(isEligible(state: snoozed, maxShows: 1, now: now.add(const Duration(days: 1))), isTrue);
      expect(isEligible(state: snoozed, maxShows: 1, now: now.add(const Duration(days: 2))), isTrue);
    });
  });

  group('applyOutcome', () {
    final now = DateTime.utc(2026, 9, 19, 12);

    test('acting and never-again end the entry', () {
      for (final outcome in [NotificationOutcome.acted, NotificationOutcome.neverAgain]) {
        final next = applyOutcome(const ServerNotificationState(count: 1), outcome, now: now);
        expect(next.count, 2);
        expect(next.done, isTrue);
        expect(next.snoozedUntil, isNull);
      }
    });

    test('later snoozes without consuming a show', () {
      final next = applyOutcome(const ServerNotificationState(count: 1), NotificationOutcome.later,
          snoozeDays: 3, now: now);
      expect(next.count, 1);
      expect(next.done, isFalse);
      expect(next.snoozedUntil, now.add(const Duration(days: 3)));
    });

    test('later supports a same-day snooze', () {
      final next = applyOutcome(ServerNotificationState.initial, NotificationOutcome.later,
          snoozeDays: 0, now: now);
      expect(next.snoozedUntil, now);
    });

    test('a plain dismissal consumes a show and clears a stale snooze', () {
      final next = applyOutcome(
        ServerNotificationState(count: 1, snoozedUntil: now.subtract(const Duration(days: 1))),
        NotificationOutcome.dismissed,
        now: now,
      );
      expect(next.count, 2);
      expect(next.snoozedUntil, isNull);
      expect(next.done, isFalse);
    });

    test('later without snooze-days behaves like a dismissal', () {
      final next = applyOutcome(const ServerNotificationState(count: 1), NotificationOutcome.later, now: now);
      expect(next.count, 2);
      expect(next.snoozedUntil, isNull);
    });
  });

  group('decodeShownCounts', () {
    test('returns an empty map for missing or unreadable data', () {
      expect(decodeShownCounts(null), isEmpty);
      expect(decodeShownCounts(""), isEmpty);
      expect(decodeShownCounts("{not json"), isEmpty);
      expect(decodeShownCounts("[1, 2]"), isEmpty);
    });

    test('round-trips encoded counts', () {
      expect(decodeShownCounts('{"go-stable-ios": 1, "sample": 3}'), {"go-stable-ios": 1, "sample": 3});
    });

    test('keeps usable entries and drops unusable ones', () {
      final decoded = decodeShownCounts('{"good": 2, "bad-type": "2", "negative": -1, "also-good": 0}');
      expect(decoded, {"good": 2, "also-good": 0});
    });

    test('does not throw on a partially corrupt map', () {
      expect(() => decodeShownCounts('{"good": 2, "bad-type": "2"}'), returnsNormally);
    });
  });

  group('mergeLegacyState', () {
    test('returns a copy when there is nothing to migrate', () {
      final state = {"a": const ServerNotificationState(count: 2)};
      final merged = mergeLegacyState(state);
      expect(merged, state);
      merged["b"] = ServerNotificationState.initial;
      expect(state, isNot(contains("b")));
    });

    test('migrates the old counts map and the shown-once list', () {
      final merged = mergeLegacyState(
        {"both": const ServerNotificationState(count: 5)},
        counts: {"both": 2, "counted": 3},
        shownOnceIds: ["both", "listed"],
      );
      expect(merged["both"]!.count, 5);
      expect(merged["counted"]!.count, 3);
      expect(merged["listed"]!.count, 1);
    });
  });

  group('localizedText', () {
    final title = {"en": "Hello", "de": "Hallo", "broken": 42};

    test('prefers the requested locale, then English, then the fallback', () {
      expect(localizedText(title, "de", "fallback"), "Hallo");
      expect(localizedText(title, "fr", "fallback"), "Hello");
      expect(localizedText({"de": "Hallo"}, "de", "fallback"), "Hallo");
      expect(localizedText({"de": "Hallo"}, "fr", "fallback"), "fallback");
    });

    test('ignores nulls, non-strings and empty strings', () {
      expect(localizedText(null, "en", "fallback"), "fallback");
      expect(localizedText("Hello", "en", "fallback"), "fallback");
      expect(localizedText(42, "en", "fallback"), "fallback");
      expect(localizedText(title, "broken", "fallback"), "Hello");
      expect(localizedText({"en": ""}, "en", "fallback"), "fallback");
      expect(localizedText({"en": 42}, "en", "fallback"), "fallback");
    });

    test('falls back when no locale is known', () {
      expect(localizedText(title, null, "fallback"), "Hello");
    });
  });

  group('tryActionUri', () {
    test('accepts http and https links', () {
      expect(tryActionUri("https://apps.apple.com/app/id1"), Uri.parse("https://apps.apple.com/app/id1"));
      expect(tryActionUri("http://example.com"), Uri.parse("http://example.com"));
    });

    test('rejects non-strings, empty and relative values', () {
      expect(tryActionUri(null), isNull);
      expect(tryActionUri(42), isNull);
      expect(tryActionUri(""), isNull);
      expect(tryActionUri("example.com"), isNull);
      expect(tryActionUri("/relative"), isNull);
    });

    test('rejects non-web schemes from the remote payload', () {
      expect(tryActionUri("javascript:alert(1)"), isNull);
      expect(tryActionUri("file:///etc/passwd"), isNull);
      expect(tryActionUri("tel:+49123"), isNull);
      expect(tryActionUri("unustasis://scooter"), isNull);
    });

    test('rejects malformed URIs', () {
      expect(tryActionUri("https://[::1"), isNull);
    });
  });
}