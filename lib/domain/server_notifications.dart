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
/// * `branch`   - exact match against `PackageInfo.appName` (iOS: "stasis for unu"
///                for Release, "stasis dev" for Debug, "stasis profile" for Profile).
/// * `platform` - exact match against `Platform.operatingSystem`.
/// * `build-number` / `min-build-number` / `max-build-number` - scope to specific
///                app build numbers from `PackageInfo.buildNumber`.
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

/// Result of comparing an entry's build scope against the running app.
enum BuildScopeMatch {
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
  String toString() =>
      'ServerNotificationState(count: $count, done: $done, snoozedUntil: $snoozedUntil)';

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
BuildScopeMatch matchBuildNumber({
  required Object? exact,
  required Object? min,
  required Object? max,
  required int? buildNumber,
}) {
  if (exact == null && min == null && max == null) return BuildScopeMatch.match;
  if (buildNumber == null) return BuildScopeMatch.malformed;

  final exactNumbers = _numbers(exact);
  if (exactNumbers == null) return BuildScopeMatch.malformed;
  if (exactNumbers.isNotEmpty && !exactNumbers.contains(buildNumber)) return BuildScopeMatch.mismatch;

  final minNumber = _number(min);
  if (minNumber == null && min != null) return BuildScopeMatch.malformed;
  if (minNumber != null && buildNumber < minNumber) return BuildScopeMatch.mismatch;

  final maxNumber = _number(max);
  if (maxNumber == null && max != null) return BuildScopeMatch.malformed;
  if (maxNumber != null && buildNumber > maxNumber) return BuildScopeMatch.mismatch;

  return BuildScopeMatch.match;
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