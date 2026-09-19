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
    ScopeMatch match({Object? exact, Object? min, Object? max, int? buildNumber = 46}) => matchBuildNumber(
          exact: exact,
          min: min,
          max: max,
          buildNumber: buildNumber,
        );

    test('an entry without a scope matches every build', () {
      expect(match(), ScopeMatch.match);
      expect(match(buildNumber: null), ScopeMatch.match);
    });

    test('matches an exact build number or a list of them', () {
      expect(match(exact: 46), ScopeMatch.match);
      expect(match(exact: 45), ScopeMatch.mismatch);
      expect(match(exact: [46, 47]), ScopeMatch.match);
      expect(match(exact: [44, 45]), ScopeMatch.mismatch);
      expect(match(exact: 46.0), ScopeMatch.match);
      // an empty list is the same as no constraint
      expect(match(exact: <int>[]), ScopeMatch.match);
    });

    test('matches min and max bounds inclusively', () {
      expect(match(min: 40), ScopeMatch.match);
      expect(match(min: 47), ScopeMatch.mismatch);
      expect(match(max: 50), ScopeMatch.match);
      expect(match(max: 45), ScopeMatch.mismatch);
      expect(match(min: 40, max: 50), ScopeMatch.match);
      expect(match(min: 40, max: 45), ScopeMatch.mismatch);
    });

    test('scopes are combined (all must match)', () {
      expect(match(exact: 46, min: 40, max: 50), ScopeMatch.match);
      expect(match(exact: 46, min: 47), ScopeMatch.mismatch);
      expect(match(exact: 46, max: 45), ScopeMatch.mismatch);
    });

    test('a scope that cannot be evaluated is malformed, never unscoped', () {
      const scope = ScopeMatch.malformed;
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

  group('matchAppId', () {
    test('an entry without the field matches every build', () {
      expect(matchAppId(value: null, applicationId: 'de.freal.unustasis'), ScopeMatch.match);
      expect(matchAppId(value: null, applicationId: null), ScopeMatch.match);
    });

    test('accepts one application id or a list, exactly', () {
      expect(matchAppId(value: 'de.freal.unustasis', applicationId: 'de.freal.unustasis'), ScopeMatch.match);
      expect(
        matchAppId(
          value: ['de.freal.unustasis', 'de.freal.unustasis.debug'],
          applicationId: 'de.freal.unustasis.debug',
        ),
        ScopeMatch.match,
      );
      expect(
        matchAppId(value: 'de.freal.unustasis', applicationId: 'de.freal.unustasis.debug'),
        ScopeMatch.mismatch,
        reason: 'the debug build needs its own entry or a wildcard',
      );
    });

    test('a trailing star matches every build type of one application', () {
      for (final id in ['de.freal.unustasis', 'de.freal.unustasis.debug']) {
        expect(matchAppId(value: 'de.freal.unustasis*', applicationId: id), ScopeMatch.match);
      }
      expect(matchAppId(value: 'de.freal.unustasis*', applicationId: 'org.librescoot.mobile.unu'), ScopeMatch.mismatch);
      expect(matchAppId(value: 'de.freal.unustasis.*', applicationId: 'de.freal.unustasis'), ScopeMatch.mismatch,
          reason: 'a prefix pattern does not match a shorter id');
    });

    test('matching is case sensitive, like the identifiers', () {
      expect(matchAppId(value: 'DE.freal.unustasis', applicationId: 'de.freal.unustasis'), ScopeMatch.mismatch);
    });

    test('an unusable scope never matches', () {
      expect(matchAppId(value: 'de.freal.unustasis', applicationId: null), ScopeMatch.malformed);
      expect(matchAppId(value: 'de.freal.unustasis', applicationId: ''), ScopeMatch.malformed);
      expect(matchAppId(value: 42, applicationId: 'de.freal.unustasis'), ScopeMatch.malformed);
      expect(matchAppId(value: ['de.freal.unustasis', 7], applicationId: 'de.freal.unustasis'), ScopeMatch.malformed);
      expect(matchAppId(value: <String>[], applicationId: 'de.freal.unustasis'), ScopeMatch.malformed);
      expect(matchAppId(value: '', applicationId: 'de.freal.unustasis'), ScopeMatch.malformed);
      expect(matchAppId(value: '*', applicationId: 'de.freal.unustasis'), ScopeMatch.malformed,
          reason: 'a bare star would broadcast to every app');
    });
  });

  group('matchInstallerStore', () {
    test('an entry without the field matches every install', () {
      expect(matchInstallerStore(value: null, installerStore: "com.apple.testflight"), ScopeMatch.match);
      expect(matchInstallerStore(value: null, installerStore: null), ScopeMatch.match);
    });

    test('accepts one store or a list', () {
      expect(
        matchInstallerStore(value: "com.apple.testflight", installerStore: "com.apple.testflight"),
        ScopeMatch.match,
      );
      expect(
        matchInstallerStore(value: ["com.apple.testflight", "com.apple"], installerStore: "com.apple"),
        ScopeMatch.match,
      );
      expect(
        matchInstallerStore(value: "com.apple.testflight", installerStore: "com.apple"),
        ScopeMatch.mismatch,
      );
    });

    test('a missing installer store matches the "none" sentinel', () {
      expect(matchInstallerStore(value: "none", installerStore: null), ScopeMatch.match);
      expect(matchInstallerStore(value: "none", installerStore: ""), ScopeMatch.match);
      expect(matchInstallerStore(value: "com.android.vending", installerStore: null), ScopeMatch.mismatch);
    });

    test('malformed values never match', () {
      expect(matchInstallerStore(value: [], installerStore: "com.apple"), ScopeMatch.malformed);
      expect(matchInstallerStore(value: 42, installerStore: "com.apple"), ScopeMatch.malformed);
      expect(matchInstallerStore(value: ["com.apple", 42], installerStore: "com.apple"), ScopeMatch.malformed);
    });
  });

  group('matchInstallTimes', () {
    final installed = DateTime.utc(2026, 9, 1);
    final updated = DateTime.utc(2026, 9, 18, 22);

    ScopeMatch match({
      Object? minInstallTime,
      Object? maxInstallTime,
      Object? minUpdateTime,
      Object? maxUpdateTime,
      DateTime? installTime,
      DateTime? updateTime,
    }) =>
        matchInstallTimes(
          minInstallTime: minInstallTime,
          maxInstallTime: maxInstallTime,
          minUpdateTime: minUpdateTime,
          maxUpdateTime: maxUpdateTime,
          installTime: installTime ?? installed,
          updateTime: updateTime ?? updated,
        );

    test('an entry without bounds matches every install', () {
      expect(match(), ScopeMatch.match);
    });

    test('bounds are inclusive and compare instants', () {
      expect(match(minUpdateTime: "2026-09-18T22:00:00Z"), ScopeMatch.match);
      expect(match(maxUpdateTime: "2026-09-18T22:00:00Z"), ScopeMatch.match);
      expect(match(minUpdateTime: "2026-09-19T00:00:00Z"), ScopeMatch.mismatch);
      expect(match(maxUpdateTime: "2026-09-18T21:59:59Z"), ScopeMatch.mismatch);
      expect(match(minInstallTime: "2026-08-01T00:00:00Z", maxInstallTime: "2026-09-15T00:00:00Z"), ScopeMatch.match);
      expect(match(minInstallTime: "2026-09-15T00:00:00Z"), ScopeMatch.mismatch);
    });

    test('install and update bounds are independent', () {
      expect(
        match(minUpdateTime: "2026-01-01T00:00:00Z", maxInstallTime: "2026-09-02T00:00:00Z"),
        ScopeMatch.match,
      );
    });

    test('a bound that cannot be checked fails closed', () {
      expect(match(minUpdateTime: "not a date"), ScopeMatch.malformed);
      expect(match(maxUpdateTime: 42), ScopeMatch.malformed);
      // the platform did not report the timestamp the bound needs
      expect(
        matchInstallTimes(
          minInstallTime: "2026-01-01T00:00:00Z",
          maxInstallTime: null,
          minUpdateTime: null,
          maxUpdateTime: null,
          installTime: null,
          updateTime: updated,
        ),
        ScopeMatch.malformed,
      );
      expect(
        matchInstallTimes(
          minInstallTime: null,
          maxInstallTime: null,
          minUpdateTime: null,
          maxUpdateTime: "2026-09-19T00:00:00Z",
          installTime: installed,
          updateTime: null,
        ),
        ScopeMatch.malformed,
      );
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
      final next =
          applyOutcome(const ServerNotificationState(count: 1), NotificationOutcome.later, snoozeDays: 3, now: now);
      expect(next.count, 1);
      expect(next.done, isFalse);
      expect(next.snoozedUntil, now.add(const Duration(days: 3)));
    });

    test('later supports a same-day snooze', () {
      final next = applyOutcome(ServerNotificationState.initial, NotificationOutcome.later, snoozeDays: 0, now: now);
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
