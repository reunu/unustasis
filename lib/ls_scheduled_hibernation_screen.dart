import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'domain/go_duration.dart';
import 'domain/hibernation_schedule.dart';
import 'scooter_service.dart';
import 'service/ble_commands.dart';

/// Configuration screen for librescoot's scheduled hibernation: a cron-based
/// schedule that hibernates the scooter at a set time and wakes it again
/// after a set duration. Settings are written to the scooter on change.
class LsScheduledHibernationScreen extends StatefulWidget {
  const LsScheduledHibernationScreen({super.key});

  @override
  State<LsScheduledHibernationScreen> createState() => _LsScheduledHibernationScreenState();
}

class _LsScheduledHibernationScreenState extends State<LsScheduledHibernationScreen> {
  // cron day-of-week indices (0 = Sunday) in display order, Monday first
  static const List<int> _dayOrder = [1, 2, 3, 4, 5, 6, 0];

  // dropdown sentinel for the "Custom…" wake-after entry
  static const int _customWakeAfterSentinel = -1;

  static const List<int> _wakeAfterPresets = [
    14400, // 4 hours
    28800, // 8 hours
    43200, // 12 hours
    86400, // 1 day
    259200, // 3 days
    604800, // 7 days
  ];

  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;
  bool _enabled = false;
  HibernationSchedule _schedule = HibernationSchedule.defaults;
  String? _rawCron; // set when the scooter has a cron we can't represent
  bool _cronUnset = false;
  Duration _wakeAfter = const Duration(hours: 8);
  bool _durationUnset = false;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so that we have a valid context with
    // the ScooterService available via Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final service = context.read<ScooterService>();
    try {
      final enabled = await getLsSettingCommand(
          service.myScooter, service.characteristicRepository, lsKeyScheduledHibernateEnabled);
      final cron = await getLsSettingCommand(
          service.myScooter, service.characteristicRepository, lsKeyScheduledHibernateCron);
      final duration = await getLsSettingCommand(
          service.myScooter, service.characteristicRepository, lsKeyScheduledHibernateDuration);
      if (!mounted) return;
      if (enabled == null) {
        // key unsupported or read failed despite the capability gate
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
        return;
      }
      setState(() {
        _enabled = enabled == "true";
        final parsed = HibernationSchedule.fromCron(cron ?? "");
        _cronUnset = (cron ?? "").trim().isEmpty;
        _rawCron = (!_cronUnset && parsed == null) ? cron : null;
        _schedule = parsed ?? HibernationSchedule.defaults;
        final parsedDuration = tryParseGoDuration(duration ?? "");
        _durationUnset = parsedDuration == null || parsedDuration <= Duration.zero;
        _wakeAfter = _durationUnset ? const Duration(hours: 8) : parsedDuration!;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _runWrite(Future<void> Function() write) async {
    setState(() => _sending = true);
    try {
      await write();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_save_success")),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_save_error",
              translationParams: {"error": e.toString()})),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _writeEnabled(bool value) => _runWrite(() async {
        final service = context.read<ScooterService>();
        if (value) {
          // First enable on a fresh scooter: persist our defaults so the
          // schedule never runs half-configured. Enabled flag goes last.
          if (_cronUnset) {
            await setLsSettingCommand(service.myScooter, service.characteristicRepository,
                lsKeyScheduledHibernateCron, _schedule.toCron());
          }
          if (_durationUnset) {
            await setLsSettingCommand(service.myScooter, service.characteristicRepository,
                lsKeyScheduledHibernateDuration, formatGoDuration(_wakeAfter));
          }
        }
        await setLsSettingCommand(service.myScooter, service.characteristicRepository,
            lsKeyScheduledHibernateEnabled, value ? "true" : "false");
        setState(() {
          if (value && _cronUnset) _cronUnset = false;
          if (value && _durationUnset) _durationUnset = false;
          _enabled = value;
        });
      });

  Future<void> _writeSchedule(HibernationSchedule newSchedule) => _runWrite(() async {
        final service = context.read<ScooterService>();
        await setLsSettingCommand(service.myScooter, service.characteristicRepository,
            lsKeyScheduledHibernateCron, newSchedule.toCron());
        setState(() {
          _schedule = newSchedule;
          _rawCron = null;
          _cronUnset = false;
        });
      });

  Future<void> _writeWakeAfter(Duration value) => _runWrite(() async {
        final service = context.read<ScooterService>();
        await setLsSettingCommand(service.myScooter, service.characteristicRepository,
            lsKeyScheduledHibernateDuration, formatGoDuration(value));
        setState(() {
          _wakeAfter = value;
          _durationUnset = false;
        });
      });

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _schedule.hour, minute: _schedule.minute),
    );
    if (picked == null || !mounted) return;
    await _writeSchedule(_schedule.copyWith(hour: picked.hour, minute: picked.minute));
  }

  void _toggleWeekday(int day) {
    final weekdays = Set<int>.from(_schedule.weekdays);
    if (weekdays.contains(day)) {
      if (weekdays.length == 1) return; // the schedule needs at least one day
      weekdays.remove(day);
    } else {
      weekdays.add(day);
    }
    _writeSchedule(_schedule.copyWith(weekdays: weekdays));
  }

  String _frequencyLabel(BuildContext context, HibernationFrequency frequency) {
    switch (frequency) {
      case HibernationFrequency.daily:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_freq_daily");
      case HibernationFrequency.weekly:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_freq_weekly");
      case HibernationFrequency.monthly:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_freq_monthly");
    }
  }

  String _weekdayLabel(BuildContext context, int day) =>
      FlutterI18n.translate(context, "weekday_short_$day");

  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  String _formatTime(BuildContext context) =>
      _formatTimeOfDay(context, TimeOfDay(hour: _schedule.hour, minute: _schedule.minute));

  String _dayOffsetLabel(BuildContext context, int offset) {
    switch (offset) {
      case 0:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_same_day");
      case 1:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_next_day");
      default:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_n_days_later",
            translationParams: {"n": offset.toString()});
    }
  }

  /// Lets the user pick the wake-up moment as a time of day plus a day
  /// offset, and converts it back to the duration the scooter stores.
  Future<void> _pickCustomWakeAfter() async {
    final scheduleMinutes = _schedule.hour * 60 + _schedule.minute;
    final currentTotal = scheduleMinutes + _wakeAfter.inMinutes;
    TimeOfDay wake = TimeOfDay(hour: (currentTotal ~/ 60) % 24, minute: currentTotal % 60);
    int daysLater = (currentTotal ~/ (24 * 60)).clamp(0, 7);

    final Duration? picked = await showDialog<Duration>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final minutes = daysLater * 24 * 60 + (wake.hour * 60 + wake.minute) - scheduleMinutes;
          final valid = minutes > 0 && minutes <= 7 * 24 * 60;
          return AlertDialog(
            title: Text(
                FlutterI18n.translate(context, "ls_scheduled_hibernation_wake_custom_title")),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_wake_at_label")),
                    TextButton(
                      onPressed: () async {
                        final pickedTime =
                            await showTimePicker(context: context, initialTime: wake);
                        if (pickedTime != null) {
                          setDialogState(() => wake = pickedTime);
                        }
                      },
                      child: Text(_formatTimeOfDay(context, wake)),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  isExpanded: true,
                  value: daysLater,
                  items: [
                    for (int offset = 0; offset <= 7; offset++)
                      DropdownMenuItem(
                        value: offset,
                        child: Text(_dayOffsetLabel(context, offset)),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => daysLater = value ?? daysLater),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(FlutterI18n.translate(context, "cancel")),
                onPressed: () => Navigator.of(context).pop(),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                ),
                onPressed:
                    valid ? () => Navigator.of(context).pop(Duration(minutes: minutes)) : null,
                child: Text(FlutterI18n.translate(context, "controls_hibernate_custom_set")),
              ),
            ],
          );
        },
      ),
    );
    if (picked != null && mounted) {
      await _writeWakeAfter(picked);
    }
  }

  String _formatCompactDuration(BuildContext context, Duration duration) {
    switch (duration.inSeconds) {
      case 14400:
        return FlutterI18n.translate(context, "ls_settings_duration_4_hours");
      case 28800:
        return FlutterI18n.translate(context, "ls_settings_duration_8_hours");
      case 43200:
        return FlutterI18n.translate(context, "ls_settings_duration_12_hours");
      case 86400:
        return FlutterI18n.translate(context, "ls_settings_duration_1_day");
      case 259200:
        return FlutterI18n.translate(context, "ls_settings_duration_3_days");
      case 604800:
        return FlutterI18n.translate(context, "ls_settings_duration_7_days");
    }
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final parts = [
      if (days > 0) "${days}d",
      if (hours > 0) "${hours}h",
      if (minutes > 0) "${minutes}m",
    ];
    return parts.isEmpty ? "0m" : parts.join(" ");
  }

  /// The wake-up time of day resulting from hibernate time + duration,
  /// spelled out when the wake falls on a later day ("06:00 the next day").
  String _formatWakeTime(BuildContext context) {
    final totalMinutes = _schedule.hour * 60 + _schedule.minute + _wakeAfter.inMinutes;
    final dayOffset = totalMinutes ~/ (24 * 60);
    final minutesOfDay = totalMinutes % (24 * 60);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutesOfDay ~/ 60, minute: minutesOfDay % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    switch (dayOffset) {
      case 0:
        return time;
      case 1:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_wake_next_day",
            translationParams: {"time": time});
      default:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_wake_days_later",
            translationParams: {"time": time, "n": dayOffset.toString()});
    }
  }

  String _summaryText(BuildContext context) {
    final time = _formatTime(context);
    final wake = _formatWakeTime(context);
    switch (_schedule.frequency) {
      case HibernationFrequency.daily:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_summary", translationParams: {
          "days": FlutterI18n.translate(context, "ls_scheduled_hibernation_every_day"),
          "time": time,
          "wake": wake,
        });
      case HibernationFrequency.weekly:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_summary", translationParams: {
          "days": _dayOrder
              .where(_schedule.weekdays.contains)
              .map((day) => _weekdayLabel(context, day))
              .join(", "),
          "time": time,
          "wake": wake,
        });
      case HibernationFrequency.monthly:
        return FlutterI18n.translate(context, "ls_scheduled_hibernation_summary_monthly",
            translationParams: {
              "day": _schedule.dayOfMonth.toString(),
              "time": time,
              "wake": wake,
            });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_title")),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
                ? _buildLoadFailed(context)
                : _buildSettings(context),
      ),
    );
  }

  Widget _buildLoadFailed(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              FlutterI18n.translate(context, "ls_scheduled_hibernation_load_error"),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: _load,
            child: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_retry")),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bedtime_outlined),
          title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_enable")),
          value: _enabled,
          onChanged: _sending ? null : _writeEnabled,
        ),
        ListTile(
          leading: const Icon(Icons.access_time_outlined),
          title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_time_title")),
          trailing: Text(
            _formatTime(context),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          enabled: !_sending,
          onTap: _pickTime,
        ),
        ListTile(
          leading: const Icon(Icons.repeat_rounded),
          title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_repeat_title")),
          trailing: DropdownButton<HibernationFrequency>(
            value: _schedule.frequency,
            items: [
              for (final frequency in HibernationFrequency.values)
                DropdownMenuItem(
                  value: frequency,
                  child: Text(_frequencyLabel(context, frequency)),
                ),
            ],
            onChanged: _sending
                ? null
                : (value) {
                    if (value != null && value != _schedule.frequency) {
                      _writeSchedule(_schedule.copyWith(frequency: value));
                    }
                  },
          ),
        ),
        if (_schedule.frequency == HibernationFrequency.weekly)
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_days_title")),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final day in _dayOrder)
                    FilterChip(
                      label: Text(_weekdayLabel(context, day)),
                      selected: _schedule.weekdays.contains(day),
                      onSelected: _sending ? null : (_) => _toggleWeekday(day),
                      // use the accent color; the theme's secondary fallback is
                      // a generic green that doesn't match the rest of the UI
                      selectedColor: Theme.of(context).colorScheme.primary,
                      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                      labelStyle: _schedule.weekdays.contains(day)
                          ? TextStyle(color: Theme.of(context).colorScheme.onPrimary)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        if (_schedule.frequency == HibernationFrequency.monthly)
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_monthday_title")),
            trailing: DropdownButton<int>(
              value: _schedule.dayOfMonth,
              items: [
                for (int day = 1; day <= 31; day++) DropdownMenuItem(value: day, child: Text("$day")),
              ],
              onChanged: _sending
                  ? null
                  : (value) {
                      if (value != null && value != _schedule.dayOfMonth) {
                        _writeSchedule(_schedule.copyWith(dayOfMonth: value));
                      }
                    },
            ),
          ),
        ListTile(
          leading: const Icon(Icons.alarm_outlined),
          title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_wake_title")),
          trailing: DropdownButton<int>(
            value: _wakeAfter.inSeconds,
            items: [
              for (final seconds in _wakeAfterPresets)
                DropdownMenuItem(
                  value: seconds,
                  child: Text(_formatCompactDuration(context, Duration(seconds: seconds))),
                ),
              if (!_wakeAfterPresets.contains(_wakeAfter.inSeconds))
                DropdownMenuItem(
                  value: _wakeAfter.inSeconds,
                  child: Text(_formatCompactDuration(context, _wakeAfter)),
                ),
              DropdownMenuItem(
                value: _customWakeAfterSentinel,
                child: Text(FlutterI18n.translate(context, "controls_hibernate_custom")),
              ),
            ],
            onChanged: _sending
                ? null
                : (value) {
                    if (value == _customWakeAfterSentinel) {
                      _pickCustomWakeAfter();
                    } else if (value != null && value != _wakeAfter.inSeconds) {
                      _writeWakeAfter(Duration(seconds: value));
                    }
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            _summaryText(context),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_rawCron != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FlutterI18n.translate(context, "ls_scheduled_hibernation_custom_cron_title"),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(_rawCron!, style: GoogleFonts.kodeMono()),
                    const SizedBox(height: 8),
                    Text(FlutterI18n.translate(
                        context, "ls_scheduled_hibernation_custom_cron_body")),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Text(
            FlutterI18n.translate(context, "ls_scheduled_hibernation_footnote"),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ),
      ],
    );
  }
}
