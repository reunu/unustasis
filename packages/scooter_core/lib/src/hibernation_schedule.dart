/// How often a hibernation schedule repeats. Maps onto the cron shapes the
/// scooter's scheduler can express (RRULE-style FREQ, INTERVAL=1).
enum HibernationFrequency { daily, weekly, monthly }

/// The app-supported subset of the scooter's hibernation cron expression:
///
///   daily:   "M H * * *"
///   weekly:  "M H * * DOW" with DOW a comma-separated list of 0-6 (0=Sunday)
///   monthly: "M H D * *" with D a single day of month 1-31
///
/// Anything outside these shapes (ranges, steps, names, month restrictions,
/// combined day-of-month + day-of-week) is treated as a custom expression by
/// the UI.
class HibernationSchedule {
  final int hour; // 0-23
  final int minute; // 0-59
  final HibernationFrequency frequency;
  final Set<int> weekdays; // weekly only: 0=Sunday .. 6=Saturday, never empty
  final int dayOfMonth; // monthly only: 1-31

  const HibernationSchedule({
    required this.hour,
    required this.minute,
    this.frequency = HibernationFrequency.daily,
    this.weekdays = allDays,
    this.dayOfMonth = 1,
  });

  static const Set<int> allDays = {0, 1, 2, 3, 4, 5, 6};

  static HibernationSchedule get defaults => const HibernationSchedule(hour: 22, minute: 0);

  String toCron() {
    switch (frequency) {
      case HibernationFrequency.daily:
        return '$minute $hour * * *';
      case HibernationFrequency.weekly:
        // always an explicit list (even all 7 days) so the expression
        // round-trips back to weekly instead of collapsing to daily
        return '$minute $hour * * ${(weekdays.toList()..sort()).join(",")}';
      case HibernationFrequency.monthly:
        return '$minute $hour $dayOfMonth * *';
    }
  }

  /// Parses the supported cron subset. Returns null for empty input or any
  /// expression outside the subset, which the UI renders as a custom
  /// expression.
  static HibernationSchedule? fromCron(String cron) {
    final fields = cron.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) return null;
    final minute = int.tryParse(fields[0]);
    final hour = int.tryParse(fields[1]);
    if (minute == null || minute < 0 || minute > 59) return null;
    if (hour == null || hour < 0 || hour > 23) return null;
    if (fields[3] != "*") return null; // month restrictions are custom

    final dom = fields[2];
    final dow = fields[4];

    if (dom == "*" && dow == "*") {
      return HibernationSchedule(hour: hour, minute: minute);
    }
    if (dom == "*") {
      final weekdays = <int>{};
      for (final token in dow.split(",")) {
        final day = int.tryParse(token);
        if (day == null || day < 0 || day > 7) return null;
        weekdays.add(day == 7 ? 0 : day); // cron allows 7 for Sunday
      }
      if (weekdays.isEmpty) return null;
      return HibernationSchedule(
        hour: hour,
        minute: minute,
        frequency: HibernationFrequency.weekly,
        weekdays: weekdays,
      );
    }
    if (dow == "*") {
      final day = int.tryParse(dom);
      if (day == null || day < 1 || day > 31) return null;
      return HibernationSchedule(
        hour: hour,
        minute: minute,
        frequency: HibernationFrequency.monthly,
        dayOfMonth: day,
      );
    }
    // both day-of-month and day-of-week restricted: cron treats that as an
    // OR, which the UI can't represent honestly
    return null;
  }

  HibernationSchedule copyWith({
    int? hour,
    int? minute,
    HibernationFrequency? frequency,
    Set<int>? weekdays,
    int? dayOfMonth,
  }) =>
      HibernationSchedule(
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        frequency: frequency ?? this.frequency,
        weekdays: weekdays ?? this.weekdays,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      );
}
