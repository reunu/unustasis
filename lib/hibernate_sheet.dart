import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'helper_widgets/header.dart';
import 'scooter_service.dart';

/// Bottom sheet offering hibernation with an optional wake timer. Shown
/// instead of the instant hibernate action on librescoot scooters that
/// support the pm:hibernate-for capability. Pops with `true` once the
/// hibernation command was sent successfully.
class HibernateSheet extends StatefulWidget {
  const HibernateSheet({super.key});

  @override
  State<HibernateSheet> createState() => _HibernateSheetState();
}

class _HibernateSheetState extends State<HibernateSheet> {
  static const List<Duration> _presets = [
    Duration(hours: 8),
    Duration(hours: 12),
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
  ];

  Duration? _wakeAfter; // null = don't wake automatically
  Duration? _customDuration;
  bool _sending = false;

  bool get _customSelected => _wakeAfter != null && !_presets.contains(_wakeAfter);

  String _presetLabel(BuildContext context, Duration duration) {
    switch (duration) {
      case const Duration(hours: 8):
        return FlutterI18n.translate(context, "ls_settings_duration_8_hours");
      case const Duration(hours: 12):
        return FlutterI18n.translate(context, "ls_settings_duration_12_hours");
      case const Duration(days: 1):
        return FlutterI18n.translate(context, "ls_settings_duration_1_day");
      case const Duration(days: 3):
        return FlutterI18n.translate(context, "ls_settings_duration_3_days");
      default:
        return FlutterI18n.translate(context, "ls_settings_duration_7_days");
    }
  }

  /// A choice chip in the app's accent color (the theme's secondary fallback
  /// is a generic green that doesn't match the rest of the UI).
  Widget _accentChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required ValueChanged<bool>? onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: colors.primary,
      checkmarkColor: colors.onPrimary,
      labelStyle: selected ? TextStyle(color: colors.onPrimary) : null,
    );
  }

  String _formatCompactDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    if (days > 0 && hours > 0) return "${days}d ${hours}h";
    if (days > 0) return "${days}d";
    return "${hours}h";
  }

  String _formatWakeTime(BuildContext context, DateTime wake) {
    final loc = MaterialLocalizations.of(context);
    final time = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(wake),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    if (wake.difference(DateTime.now()) < const Duration(hours: 24)) {
      return time;
    }
    return "${loc.formatMediumDate(wake)} $time";
  }

  Future<void> _pickCustomDuration() async {
    int days = _customDuration?.inDays ?? 0;
    int hours = _customDuration != null ? _customDuration!.inHours % 24 : 8;
    final Duration? picked = await showDialog<Duration>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final total = Duration(days: days, hours: hours);
          final valid = total > Duration.zero && total <= const Duration(days: 7);
          return AlertDialog(
            title: Text(FlutterI18n.translate(context, "controls_hibernate_custom_title")),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(FlutterI18n.translate(context, "controls_hibernate_custom_days")),
                    DropdownButton<int>(
                      value: days,
                      items: [
                        for (int d = 0; d <= 7; d++) DropdownMenuItem(value: d, child: Text("$d")),
                      ],
                      onChanged: (value) => setDialogState(() => days = value ?? days),
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(FlutterI18n.translate(context, "controls_hibernate_custom_hours")),
                    DropdownButton<int>(
                      value: hours,
                      items: [
                        for (int h = 0; h <= 23; h++) DropdownMenuItem(value: h, child: Text("$h")),
                      ],
                      onChanged: (value) => setDialogState(() => hours = value ?? hours),
                    ),
                  ],
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
                onPressed: valid ? () => Navigator.of(context).pop(total) : null,
                child: Text(FlutterI18n.translate(context, "controls_hibernate_custom_set")),
              ),
            ],
          );
        },
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customDuration = picked;
        _wakeAfter = picked;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() => _sending = true);
    try {
      final service = context.read<ScooterService>();
      if (_wakeAfter == null) {
        await service.hibernate();
      } else {
        await service.hibernateFor(_wakeAfter!);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString());
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wakeTime = _wakeAfter != null ? DateTime.now().add(_wakeAfter!) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Header(
              FlutterI18n.translate(context, "controls_hibernate_sheet_title"),
              subtitle: FlutterI18n.translate(context, "controls_hibernate_sheet_subtitle"),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _accentChip(
                context,
                label: FlutterI18n.translate(context, "controls_hibernate_no_wake"),
                selected: _wakeAfter == null,
                onSelected: _sending ? null : (_) => setState(() => _wakeAfter = null),
              ),
              for (final preset in _presets)
                _accentChip(
                  context,
                  label: _presetLabel(context, preset),
                  selected: _wakeAfter == preset,
                  onSelected: _sending ? null : (_) => setState(() => _wakeAfter = preset),
                ),
              _accentChip(
                context,
                label: _customSelected || _customDuration != null
                    ? FlutterI18n.translate(context, "controls_hibernate_custom_value",
                        translationParams: {
                          "duration": _formatCompactDuration(_customDuration ?? _wakeAfter!)
                        })
                    : FlutterI18n.translate(context, "controls_hibernate_custom"),
                selected: _customSelected,
                onSelected: _sending ? null : (_) => _pickCustomDuration(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _sending ? null : _confirm,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.nightlight_outlined),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FlutterI18n.translate(context, "controls_hibernate_confirm")),
                if (wakeTime != null)
                  Text(
                    FlutterI18n.translate(context, "controls_hibernate_wakes_at",
                        translationParams: {"time": _formatWakeTime(context, wakeTime)}),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}
