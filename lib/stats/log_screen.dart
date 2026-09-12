import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';

import '../domain/saved_scooter.dart';
import '../domain/statistics_helper.dart';
import '../scooter_service.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  String getScooterName(BuildContext context, bool multipleScootersInLog, String scooterId) {
    Map<String, SavedScooter> scooters = context.read<ScooterService>().savedScooters;
    if (!multipleScootersInLog || !scooters.containsKey(scooterId)) {
      return FlutterI18n.translate(context, "activity_log_generic_scooter");
    }
    return scooters[scooterId]?.name ?? FlutterI18n.translate(context, "activity_log_generic_scooter");
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    if (DateUtils.isSameDay(local, now)) {
      return FlutterI18n.translate(context, "activity_log_today_at", translationParams: {"time": time});
    }
    if (DateUtils.isSameDay(local, now.subtract(const Duration(days: 1)))) {
      return FlutterI18n.translate(context, "activity_log_yesterday_at", translationParams: {"time": time});
    }
    return "${localizations.formatMediumDate(local)} · $time";
  }

  String? _sourceDescription(BuildContext context, EventSource source) {
    return switch (source) {
      EventSource.app => FlutterI18n.translate(context, "activity_log_source_app"),
      EventSource.background => FlutterI18n.translate(context, "activity_log_source_background"),
      EventSource.auto => FlutterI18n.translate(context, "activity_log_source_auto"),
      EventSource.unknown => null,
    };
  }

  Widget _eventIcon(BuildContext context, EventType eventType) {
    return switch (eventType) {
      EventType.lock => const Icon(Icons.lock_outline_rounded),
      EventType.unlock => const Icon(Icons.lock_open_outlined),
      EventType.openSeat => SvgPicture.asset(
          "assets/icons/librescoot-seatbox-open.svg",
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(
            IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            BlendMode.srcIn,
          ),
        ),
      EventType.hibernate => const Icon(Icons.bedtime_outlined),
      EventType.wakeUp => const Icon(Icons.wb_sunny_outlined),
      EventType.unknown => const Icon(Icons.history_outlined),
    };
  }

  String? _batteryDescription(BuildContext context, LogEntry log) {
    final values = <String>[];
    if (log.soc1 != null && log.soc1! > 0) {
      values.add(FlutterI18n.translate(
        context,
        "activity_log_main_battery",
        translationParams: {"soc": log.soc1.toString()},
      ));
    }
    if (log.soc2 != null && log.soc2! > 0) {
      values.add(FlutterI18n.translate(
        context,
        "activity_log_second_battery",
        translationParams: {"soc": log.soc2.toString()},
      ));
    }
    return values.isEmpty ? null : values.join(" · ");
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "activity_log_title")),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(FlutterI18n.translate(context, "activity_log_disclaimer")),
          ),
          const _ActivityLogToggle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: errorColor,
                  side: BorderSide(color: errorColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(FlutterI18n.translate(context, "activity_log_clear")),
                onPressed: () async {
                  final confirm = await _confirmClearLogs(context);
                  if (confirm && context.mounted) {
                    await StatisticsHelper().clearEventLogs();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(FlutterI18n.translate(context, "activity_log_cleared"))),
                    );
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<LogEntry>>(
              future: StatisticsHelper().getEventLogs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(FlutterI18n.translate(context, "activity_log_error")));
                }
                final logs = snapshot.data ?? [];
                if (logs.isEmpty) {
                  return Center(child: Text(FlutterI18n.translate(context, "activity_log_empty")));
                }
                final multipleScootersInLog = logs.map((entry) => entry.scooterId).toSet().length > 1;
                logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final details = <String>[
                      _formatTimestamp(context, log.timestamp),
                      if (_sourceDescription(context, log.source) case final source?) source,
                      if (_batteryDescription(context, log) case final battery?) battery,
                    ];
                    return ListTile(
                      title: Text(FlutterI18n.translate(
                        context,
                        "event_type_${log.eventType.toString().toLowerCase().split('.').last}",
                        translationParams: {
                          "scooterName": getScooterName(context, multipleScootersInLog, log.scooterId),
                        },
                      )),
                      subtitle: Text(details.join("\n")),
                      leading: _eventIcon(context, log.eventType),
                      trailing:
                          log.location != null && (log.location!.latitude != 0.0 || log.location!.longitude != 0.0)
                              ? IconButton(
                                  icon: const Icon(Icons.map_outlined),
                                  onPressed: () => MapsLauncher.launchCoordinates(
                                    log.location!.latitude,
                                    log.location!.longitude,
                                  ),
                                )
                              : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClearLogs(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_title")),
            content: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_message")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(FlutterI18n.translate(context, "cancel")),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_button")),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _ActivityLogToggle extends StatefulWidget {
  const _ActivityLogToggle();

  @override
  State<_ActivityLogToggle> createState() => _ActivityLogToggleState();
}

class _ActivityLogToggleState extends State<_ActivityLogToggle> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await StatisticsHelper().isEventLoggingEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _enabled = enabled);
    await StatisticsHelper().setEventLoggingEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.history_outlined),
      title: Text(FlutterI18n.translate(context, "activity_log_store")),
      subtitle: Text(FlutterI18n.translate(context, "activity_log_store_description")),
      value: _enabled ?? true,
      onChanged: _enabled == null ? null : _setEnabled,
    );
  }
}
