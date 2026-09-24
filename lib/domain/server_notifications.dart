/// Pure helpers for the server-pushed notification entries published in
/// `docs/notifications.json` and shown by `showServerNotifications`.
///
/// Everything here is side-effect free so it can be unit tested: the widget layer
/// only fetches the payload, asks these helpers whether an entry applies and what
/// the user's choice means, and persists the result.
///
/// Supported fields, all optional except `id`, `timestamp`, `duration-days`,
/// `title` and `body`:
///
/// * `app-id`   - exact match against `PackageInfo.packageName`, the application id or
///                bundle id (`de.freal.unustasis`, plus `.debug` on Android). A pattern
///                ending in `*` matches every application id with that prefix, so one
///                entry covers the release and debug builds. Takes precedence over
///                `branch`, which only exists for feeds published before app ids.
/// * `branch`   - exact match against `PackageInfo.appName`, the localized display name
///                (iOS: "stasis for unu" for Release, "stasis dev" for Debug, "stasis
///                profile" for Profile). Prefer `app-id`: a rename or a localized app
///                name silently stops matching, and one display name cannot describe the
///                release, debug and profile builds at once.
/// * `platform` - exact match against `Platform.operatingSystem`.
/// * `build-number` / `min-build-number` / `max-build-number` - scope to specific
///                app build numbers from `PackageInfo.buildNumber`.
/// * `installer-store` - scope to how the app was installed, one string or a list:
///                `com.apple.testflight`/`com.apple` on iOS, `com.android.vending` for
///                Play on Android. The sentinel `none` matches an app installed
///                without install source information.
/// * `min-install-time` / `max-install-time` / `min-update-time` / `max-update-time` -
///                scope to when this installation was first installed or last updated,
///                from `PackageInfo.installTime`/`updateTime` (RFC3339 bounds, inclusive).
/// * `timestamp` + `duration-days` - the entry is valid from `timestamp` up to and
///                including `timestamp + duration-days`.
/// * `max-shows` - how often the entry may be shown per installation, defaults to 1.
/// * `snooze-days` - turns the dismiss button into a real "Later": the choice does
///                not count towards `max-shows` and the entry returns after that many
///                days. Without it, dismissing consumes a show like it always did.
/// * `never-text` - adds a "Don't show again" button that ends the entry for good.
///
/// Targeting is deliberately fail-closed: an entry with a build scope that cannot be
/// evaluated (unknown build number, malformed field) is not shown.
library;

import 'dart:convert';

/// Preference key holding the per-notification state map.
const kNotificationStatePrefKey = 'serverNotificationState';

/// Preference key of the counts map introduced by the build-scoping change before it
/// stored the full state. Read once for migration.
const kShownCountsPrefKey = 'shownServerNotificationCounts';

/// Preference key of the original "shown once" string list, kept for migration only.
const kLegacyShownPrefKey = 'shownServerNotifications';

/// Result of comparing an entry's scope against the running app.
enum ScopeMatch {
  /// No scope configured, or the running build is inside it.
  match,

  /// A scope is configured and the running build is outside it.
  mismatch,

  /// A scope is configured but cannot be evaluated (bad type, unknown build number).
  /// Callers should log this and treat it as [mismatch].
  malformed,
}

/// What the user did with a notification dialog.
enum NotificationOutcome {
  /// The primary action button (opens `action-url`) was pressed. Ends the entry.
  acted,

  /// "Don't show again" was pressed. Ends the entry.
  neverAgain,

  /// "Later" was pressed, or the dialog was dismissed on an entry that offers a
  /// snooze. Does not consume a show.
  later,

  /// The dialog was dismissed on an entry without `snooze-days`. Consumes a show.
  dismissed,
}

/// Per-notification, per-installation state.
class ServerNotificationState {
  const ServerNotificationState({this.count = 0, this.done = false, this.snoozedUntil});

  /// How often the entry has been shown.
  final int count;

  /// The user ended the entry through the primary action or "Don't show again".
  final bool done;

  /// A snooze set by "Later", until which the entry is not shown.
  final DateTime? snoozedUntil;

  static const ServerNotificationState initial = ServerNotificationState();

  @override
  bool operator ==(Object other) =>
      other is ServerNotificationState &&
      other.count == count &&
      other.done == done &&
      other.snoozedUntil == snoozedUntil;

  @override
  int get hashCode => Object.hash(count, done, snoozedUntil);

  @override
  String toString() => 'ServerNotificationState(count: $count, done: $done, snoozedUntil: $snoozedUntil)';

  Map<String, Object?> toJson() => {
        'count': count,
        if (done) 'done': true,
        if (snoozedUntil != null) 'snoozed-until': snoozedUntil!.toIso8601String(),
      };

  /// Reads either the current object shape or a bare count from the earlier
  /// `{id: count}` map. Returns null when the value is unusable.
  static ServerNotificationState? tryParse(Object? value) {
    if (value is num) {
      final count = value.toInt();
      return count < 0 ? null : ServerNotificationState(count: count);
    }
    if (value is! Map) return null;
    final count = value['count'];
    if (count != null && count is! num) return null;
    final parsedCount = count == null ? 0 : (count as num).toInt();
    if (parsedCount < 0) return null;
    final done = value['done'];
    if (done != null && done is! bool) return null;
    final rawSnoozedUntil = value['snoozed-until'];
    if (rawSnoozedUntil != null && rawSnoozedUntil is! String) return null;
    final snoozedUntil = rawSnoozedUntil == null ? null : DateTime.tryParse(rawSnoozedUntil as String);
    if (rawSnoozedUntil != null && snoozedUntil == null) return null;
    return ServerNotificationState(
      count: parsedCount,
      done: done == true,
      snoozedUntil: snoozedUntil,
    );
  }
}

/// Whether the entry may be shown right now: not ended by the user, still inside
/// `max-shows`, and not snoozed.
bool isEligible({required ServerNotificationState state, required int maxShows, required DateTime now}) {
  if (state.done) return false;
  if (state.count >= maxShows) return false;
  final snoozedUntil = state.snoozedUntil;
  if (snoozedUntil != null && now.isBefore(snoozedUntil)) return false;
  return true;
}

/// Applies a user's choice to [state].
///
/// [snoozeDays] is the entry's `snooze-days`, or null when the entry has no real
/// "Later". A `later` outcome without a snooze behaves like [NotificationOutcome.dismissed],
/// so a payload that loses its `snooze-days` cannot turn into a dialog on every launch.
ServerNotificationState applyOutcome(
  ServerNotificationState state,
  NotificationOutcome outcome, {
  int? snoozeDays,
  required DateTime now,
}) {
  switch (outcome) {
    case NotificationOutcome.acted:
    case NotificationOutcome.neverAgain:
      return ServerNotificationState(count: state.count + 1, done: true);
    case NotificationOutcome.later:
      if (snoozeDays == null) {
        return applyOutcome(state, NotificationOutcome.dismissed, now: now);
      }
      return ServerNotificationState(
        count: state.count,
        done: false,
        snoozedUntil: now.add(Duration(days: snoozeDays)),
      );
    case NotificationOutcome.dismissed:
      return ServerNotificationState(count: state.count + 1);
  }
}

/// Reads `duration-days` or `snooze-days`, accepting whole numbers written as JSON
/// doubles. Returns null for missing, malformed or negative values.
int? parseDurationDays(Object? value) {
  if (value is! num) return null;
  if (value.isNaN || value.isInfinite) return null;
  final days = value.toInt();
  return days < 0 ? null : days;
}

/// Reads `max-shows`, defaulting to 1 (shown once) for missing or malformed values.
/// Non-positive values would disable the entry entirely, so they fall back to 1.
int maxShowsOf(Object? value) {
  if (value is! num || value.isNaN || value.isInfinite) return 1;
  final shows = value.toInt();
  return shows < 1 ? 1 : shows;
}

/// Whether [now] is inside the entry's validity window. Both ends are inclusive.
bool isWithinWindow({required DateTime start, required int durationDays, required DateTime now}) {
  if (now.isBefore(start)) return false;
  return !now.isAfter(start.add(Duration(days: durationDays)));
}

/// Compares the optional `build-number` (number or list of numbers),
/// `min-build-number` and `max-build-number` fields against [buildNumber].
///
/// An entry without any of the fields applies to every build. When a scope is set
/// and [buildNumber] is unknown, the entry is not shown.
ScopeMatch matchBuildNumber({
  required Object? exact,
  required Object? min,
  required Object? max,
  required int? buildNumber,
}) {
  if (exact == null && min == null && max == null) return ScopeMatch.match;
  if (buildNumber == null) return ScopeMatch.malformed;

  final exactNumbers = _numbers(exact);
  if (exactNumbers == null) return ScopeMatch.malformed;
  if (exactNumbers.isNotEmpty && !exactNumbers.contains(buildNumber)) return ScopeMatch.mismatch;

  final minNumber = _number(min);
  if (minNumber == null && min != null) return ScopeMatch.malformed;
  if (minNumber != null && buildNumber < minNumber) return ScopeMatch.mismatch;

  final maxNumber = _number(max);
  if (maxNumber == null && max != null) return ScopeMatch.malformed;
  if (maxNumber != null && buildNumber > maxNumber) return ScopeMatch.mismatch;

  return ScopeMatch.match;
}

/// Compares the optional `app-id` field against [applicationId], the app's application
/// id or bundle id from `PackageInfo.packageName`. A pattern ending in `*` matches every
/// application id with that prefix, which is how one entry covers the release, debug and
/// profile builds on Android; iOS uses a single bundle id for all of them.
///
/// Exact matching is case sensitive, like the identifiers themselves. An unusable scope
/// (no application id known, a non-string entry, an empty list, or a bare `*`) does not
/// match: the same fail-closed rule as the other scopes.
ScopeMatch matchAppId({required Object? value, required String? applicationId}) {
  if (value == null) return ScopeMatch.match;
  final wanted = _strings(value);
  if (wanted == null || wanted.isEmpty) return ScopeMatch.malformed;
  final current = applicationId;
  if (current == null || current.isEmpty) return ScopeMatch.malformed;
  for (final pattern in wanted) {
    if (pattern.length < 2 ||
        (pattern.contains('*') && (pattern.indexOf('*') != pattern.length - 1))) {
      return ScopeMatch.malformed;
    }
  }
  for (final pattern in wanted) {
    if (pattern.endsWith('*')) {
      if (current.startsWith(pattern.substring(0, pattern.length - 1))) return ScopeMatch.match;
    } else if (pattern == current) {
      return ScopeMatch.match;
    }
  }
  return ScopeMatch.mismatch;
}

/// Compares the optional `installer-store` field against [installerStore], the package
/// that installed the app: `com.apple.testflight` for TestFlight, `com.apple` for the
/// App Store, `com.android.vending` for Play. A development build installed from Xcode
/// also reports `com.apple`, so this scopes beta builds but does not single out the
/// store.
ScopeMatch matchInstallerStore({required Object? value, required String? installerStore}) {
  if (value == null) return ScopeMatch.match;
  final wanted = _strings(value);
  // an empty list would silently match nothing, which is always an authoring mistake
  if (wanted == null || wanted.isEmpty) return ScopeMatch.malformed;
  final current = installerStore == null || installerStore.isEmpty ? 'none' : installerStore;
  return wanted.contains(current) ? ScopeMatch.match : ScopeMatch.mismatch;
}

/// Compares the optional `min-install-time`, `max-install-time`, `min-update-time` and
/// `max-update-time` fields against when this installation was first installed and last
/// updated. Bounds are RFC3339 strings and inclusive.
///
/// These are install dates, not build dates: the platform does not record when the
/// running binary was compiled. When a bound is set but the platform reports no
/// timestamp for it, the entry is not shown.
ScopeMatch matchInstallTimes({
  required Object? minInstallTime,
  required Object? maxInstallTime,
  required Object? minUpdateTime,
  required Object? maxUpdateTime,
  required DateTime? installTime,
  required DateTime? updateTime,
}) {
  if (minInstallTime == null && maxInstallTime == null && minUpdateTime == null && maxUpdateTime == null) {
    return ScopeMatch.match;
  }
  final minInstall = _timeBound(minInstallTime);
  final maxInstall = _timeBound(maxInstallTime);
  final minUpdate = _timeBound(minUpdateTime);
  final maxUpdate = _timeBound(maxUpdateTime);
  if ((minInstallTime != null && minInstall == null) ||
      (maxInstallTime != null && maxInstall == null) ||
      (minUpdateTime != null && minUpdate == null) ||
      (maxUpdateTime != null && maxUpdate == null)) {
    return ScopeMatch.malformed;
  }
  if (minInstall != null || maxInstall != null) {
    if (installTime == null) return ScopeMatch.malformed;
    if (minInstall != null && installTime.isBefore(minInstall)) return ScopeMatch.mismatch;
    if (maxInstall != null && installTime.isAfter(maxInstall)) return ScopeMatch.mismatch;
  }
  if (minUpdate != null || maxUpdate != null) {
    if (updateTime == null) return ScopeMatch.malformed;
    if (minUpdate != null && updateTime.isBefore(minUpdate)) return ScopeMatch.mismatch;
    if (maxUpdate != null && updateTime.isAfter(maxUpdate)) return ScopeMatch.mismatch;
  }
  return ScopeMatch.match;
}

/// Parses an RFC3339 time bound. Null means "missing or unusable", callers tell those
/// apart by looking at the raw value.
DateTime? _timeBound(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// Reads a single string or a list of strings. Null means "malformed".
List<String>? _strings(Object? value) {
  if (value is String) return [value];
  if (value is! List) return null;
  final strings = <String>[];
  for (final entry in value) {
    if (entry is! String) return null;
    strings.add(entry);
  }
  return strings;
}

/// Reads a single build number, accepting JSON doubles. Null means "not a number".
num? _number(Object? value) {
  if (value is num && !value.isNaN && !value.isInfinite) return value;
  return null;
}

/// Reads `build-number` as a list of build numbers. An empty list means "no
/// constraint" (same as omitting the field), null means "malformed".
List<num>? _numbers(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    final numbers = <num>[];
    for (final entry in value) {
      final number = _number(entry);
      if (number == null) return null;
      numbers.add(number);
    }
    return numbers;
  }
  final number = _number(value);
  return number == null ? null : [number];
}

/// Parses the persisted notification state map.
///
/// Individual unusable entries are dropped rather than failing the whole map, so one
/// bad value cannot reset the state of every other notification.
Map<String, ServerNotificationState> decodeNotificationState(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  final decoded = _tryDecode(raw);
  if (decoded is! Map) return {};

  final state = <String, ServerNotificationState>{};
  decoded.forEach((key, value) {
    if (key is! String) return;
    final parsed = ServerNotificationState.tryParse(value);
    if (parsed == null) return;
    state[key] = parsed;
  });
  return state;
}

/// Encodes the notification state map for persistence.
String encodeNotificationState(Map<String, ServerNotificationState> state) =>
    json.encode(state.map((id, value) => MapEntry(id, value.toJson())));

/// Parses the `{id: shown count}` map written by earlier builds.
Map<String, int> decodeShownCounts(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  final decoded = _tryDecode(raw);
  if (decoded is! Map) return {};

  final counts = <String, int>{};
  decoded.forEach((key, value) {
    if (key is! String || value is! num) return;
    final count = value.toInt();
    if (count < 0) return;
    counts[key] = count;
  });
  return counts;
}

Object? _tryDecode(String raw) {
  try {
    return json.decode(raw);
  } catch (_) {
    return null;
  }
}

/// Migrates the earlier `{id: count}` map and the original shown-once id list into
/// [state], keeping whatever the newer state already recorded.
Map<String, ServerNotificationState> mergeLegacyState(
  Map<String, ServerNotificationState> state, {
  Map<String, int> counts = const {},
  List<String>? shownOnceIds,
}) {
  final merged = Map.of(state);
  counts.forEach((id, count) {
    merged.putIfAbsent(id, () => ServerNotificationState(count: count));
  });
  for (final id in shownOnceIds ?? const <String>[]) {
    merged.putIfAbsent(id, () => const ServerNotificationState(count: 1));
  }
  return merged;
}

/// Picks the text for [languageCode] from a localized field, falling back to `en`
/// and then to [fallback]. Non-string values are ignored so a malformed payload
/// cannot reach a `Text` widget.
String localizedText(Object? field, String? languageCode, String fallback) {
  if (field is! Map) return fallback;
  final localized = languageCode == null ? null : field[languageCode];
  if (localized is String && localized.isNotEmpty) return localized;
  final english = field['en'];
  if (english is String && english.isNotEmpty) return english;
  return fallback;
}

/// Parses `action-url`. Only http(s) links are accepted: the payload is fetched
/// from a remote file, and other schemes could open unrelated apps.
Uri? tryActionUri(Object? url) {
  if (url is! String || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}
