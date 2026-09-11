import 'package:scooter_core/actions.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import '../../domain/alarm_status.dart';
import '../presentation/alarm_state.dart';
import 'ls_keycard_screen.dart';
import 'ls_ota_screen.dart';
import 'ls_scheduled_hibernation_screen.dart';
import '../../scooter_service.dart';
import '../../state/vehicle_status.dart';

class LsSettingsScreen extends StatefulWidget {
  const LsSettingsScreen({super.key});

  @override
  State<LsSettingsScreen> createState() => _LsSettingsScreenState();
}

class _LsSettingsScreenState extends State<LsSettingsScreen> {
  bool _isUpdatingUsbMode = false;
  bool _isSendingTime = false;
  bool _isSendingAutoLock = false;
  int? _autoLockDuration;
  bool _isSendingAutoHibernate = false;
  int? _autoHibernateDuration;
  int? _keycardCount;
  bool _keycardCountLoaded = false;
  bool _isSendingApn = false;
  bool _apnLoaded = false;
  String? _apn;
  bool _isSendingBatteryKeepActive = false;
  bool? _batteryKeepActive;
  bool _batteryKeepActiveLoaded = false;
  bool _isSendingAlarmEnabled = false;
  bool? _alarmEnabled;
  bool _isSendingAlarmHonk = false;
  bool? _alarmHonk;
  bool _alarmSettingsLoaded = false;

  ScooterService? _service;
  String? _loadedScooterId;
  bool _wasConnected = false;
  int _requestGeneration = 0;

  bool get _connected => context.read<ScooterService>().connected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(service, _service)) return;
    _service?.removeListener(_connectionChanged);
    _wasConnected = false;
    _loadedScooterId = null;
    _requestGeneration++;
    _service = service;
    service.addListener(_connectionChanged);
    _connectionChanged();
  }

  void _connectionChanged() {
    final service = _service!;
    final connected = service.connected;
    final id = service.currentScooterId;
    if (_wasConnected == connected && _loadedScooterId == id) return;
    _wasConnected = connected;
    _loadedScooterId = id;
    final generation = ++_requestGeneration;
    _keycardCount = null;
    _keycardCountLoaded = false;
    _apn = null;
    _apnLoaded = false;
    _batteryKeepActive = null;
    _batteryKeepActiveLoaded = false;
    _alarmEnabled = null;
    _alarmHonk = null;
    _alarmSettingsLoaded = false;
    _isUpdatingUsbMode = false;
    _isSendingTime = false;
    _isSendingAutoLock = false;
    _isSendingAutoHibernate = false;
    _isSendingApn = false;
    _isSendingBatteryKeepActive = false;
    _isSendingAlarmEnabled = false;
    _isSendingAlarmHonk = false;
    _autoLockDuration = null;
    _autoHibernateDuration = null;
    if (!connected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _requestGeneration || !_connected) return;
      _getKeycardCount();
      _getApn();
      _getBatteryKeepActive();
      _getAlarmSettings();
    });
  }

  // A screen-local generation also rejects A→disconnect→A completions.
  bool Function() _captureRequest() {
    final generation = _requestGeneration;
    final service = _service!;
    final id = service.currentScooterId;
    return () => mounted && generation == _requestGeneration &&
        service.connected && service.currentScooterId == id;
  }

  List<Widget> _connectionRequiredItems(List<Widget> items) {
    if (_connected) return items;
    return items.map((item) => item is ListTile ? ListTile(
      enabled: false,
      leading: item.leading,
      title: item.title,
      subtitle: Text(FlutterI18n.translate(context, 'settings_scooter_disconnected')),
      trailing: const Icon(Icons.bluetooth_disabled),
    ) : item).toList();
  }

  // Owned here rather than per-dialog. showDialog's future completes on pop,
  // while the route is still animating out with the TextField attached, so a
  // controller disposed right after the await is torn down under a live field.
  final TextEditingController _apnController = TextEditingController();

  @override
  void dispose() {
    _service?.removeListener(_connectionChanged);
    _requestGeneration++;
    _apnController.dispose();
    super.dispose();
  }

  Future<void> _getKeycardCount() async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    int? count;
    try {
      count = await context.read<ScooterService>().actions.countKeycards();
    } catch (_) {
      // A lost connection has no current keycard count.
    }
    if (!isCurrent()) return;
    setState(() {
      _keycardCount = count;
      _keycardCountLoaded = true;
    });
  }

  Future<void> _getApn() async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    String? apn;
    try {
      apn = await context.read<ScooterService>().getCellularApn();
    } catch (e) {
      apn = null;
    }
    if (!isCurrent()) return;
    setState(() {
      _apn = apn;
      _apnLoaded = true;
    });
  }

  Future<void> _getBatteryKeepActive() async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    bool? enabled;
    try {
      enabled = await context.read<ScooterService>().getBatteryKeepActive();
    } catch (e) {
      enabled = null;
    }
    if (!isCurrent()) return;
    setState(() {
      _batteryKeepActive = enabled;
      _batteryKeepActiveLoaded = true;
    });
  }

  Future<void> _setBatteryKeepActive(bool enabled) async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    setState(() {
      _isSendingBatteryKeepActive = true;
    });
    try {
      await context.read<ScooterService>().setBatteryKeepActive(enabled);
      if (!mounted || !isCurrent()) return;
      setState(() {
        _batteryKeepActive = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
              context,
              enabled
                  ? "ls_settings_battery_keep_active_on_success"
                  : "ls_settings_battery_keep_active_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      // The scooter kept its old value, so re-read rather than leaving the
      // switch showing something the scooter never accepted.
      unawaited(_getBatteryKeepActive());
    } finally {
      if (mounted && isCurrent()) {
        setState(() {
          _isSendingBatteryKeepActive = false;
        });
      }
    }
  }

  Future<void> _getAlarmSettings() async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    bool? enabled;
    bool? honk;
    try {
      final service = context.read<ScooterService>();
      enabled = await service.getAlarmEnabled();
      if (!isCurrent()) return;
      if (enabled != null) honk = await service.getAlarmHonk();
    } catch (e) {
      enabled = null;
      honk = null;
    }
    if (!isCurrent()) return;
    setState(() {
      _alarmEnabled = enabled;
      _alarmHonk = honk;
      _alarmSettingsLoaded = true;
    });
  }

  Future<void> _setAlarmEnabled(bool enabled) async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    setState(() {
      _isSendingAlarmEnabled = true;
    });
    try {
      await context.read<ScooterService>().setAlarmEnabled(enabled);
      if (!mounted || !isCurrent()) return;
      setState(() {
        _alarmEnabled = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
              context, enabled ? "ls_settings_alarm_on_success" : "ls_settings_alarm_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_alarm_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted && isCurrent()) {
        setState(() {
          _isSendingAlarmEnabled = false;
        });
      }
    }
  }

  Future<void> _setAlarmHonk(bool enabled) async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    setState(() {
      _isSendingAlarmHonk = true;
    });
    try {
      await context.read<ScooterService>().setAlarmHonk(enabled);
      if (!mounted || !isCurrent()) return;
      setState(() {
        _alarmHonk = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
              context, enabled ? "ls_settings_alarm_honk_on_success" : "ls_settings_alarm_honk_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted && isCurrent()) {
        setState(() {
          _isSendingAlarmHonk = false;
        });
      }
    }
  }

  /// Answers "would the scooter notice if someone moved it right now?", plus
  /// the wake timer and last trigger when there are any.
  String _alarmWatchSubtitle(BuildContext context, VehicleStatus vehicle) {
    final sources = vehicle.alarmWakeSources;
    final parts = <String>[];
    if (sources != null) {
      parts.add(FlutterI18n.translate(context,
          sources.motionWouldWake ? "ls_settings_alarm_watch_motion_on" : "ls_settings_alarm_watch_motion_off"));
      if (sources.wakeTimerDuration != null) {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_timer",
            translationParams: {"duration": _formatDuration(sources.wakeTimerDuration!)}));
      }
    }
    final trigger = vehicle.alarmLastTrigger;
    if (trigger != null) {
      final source = FlutterI18n.translate(context, "alarm_trigger_${trigger.source}");
      if (trigger.timestamp != null) {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_last_trigger",
            translationParams: {"source": source, "when": _formatTimestamp(context, trigger.timestamp!)}));
      } else {
        parts.add(FlutterI18n.translate(context, "ls_settings_alarm_watch_last_trigger_unknown_time",
            translationParams: {"source": source}));
      }
    }
    if (parts.isEmpty) {
      return FlutterI18n.translate(context, "ls_settings_alarm_watch_loading");
    }
    return parts.join(" ");
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final parts = [
      if (hours > 0) "${hours}h",
      if (minutes > 0) "${minutes}m",
    ];
    return parts.isEmpty ? "${duration.inSeconds}s" : parts.join(" ");
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final local = timestamp.toLocal();
    final loc = MaterialLocalizations.of(context);
    final time = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return "${loc.formatMediumDate(local)} $time";
  }

  String _apnSubtitle(BuildContext context) {
    if (!_apnLoaded) {
      return FlutterI18n.translate(context, "ls_settings_apn_loading");
    }
    if (_apn == null) {
      return FlutterI18n.translate(context, "ls_settings_apn_unknown");
    }
    if (_apn!.isEmpty) {
      return FlutterI18n.translate(context, "ls_settings_apn_unset");
    }
    return _apn!;
  }

  String? _apnErrorText(BuildContext context, ApnProblem? problem) {
    switch (problem) {
      // An empty field is the starting state, so it only disables Save
      // instead of also complaining at the user.
      case null:
      case ApnProblem.empty:
        return null;
      case ApnProblem.invalidCharacters:
        return FlutterI18n.translate(context, "ls_settings_apn_invalid_chars");
      case ApnProblem.tooLong:
        return FlutterI18n.translate(context, "ls_settings_apn_invalid_length",
            translationParams: {"max": maxApnLength.toString()});
    }
  }

  Future<void> _editApn() async {
    if (!mounted || !_connected) return;
    final isCurrent = _captureRequest();
    final controller = _apnController..text = _apn ?? "";
    final ({bool clear, String value})? picked = await showDialog<({bool clear, String value})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final trimmed = controller.text.trim();
          final problem = checkApn(trimmed);
          return AlertDialog(
            title: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_dialog_title")),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_dialog_body")),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textCapitalization: TextCapitalization.none,
                  maxLength: maxApnLength,
                  decoration: InputDecoration(
                    hintText: FlutterI18n.translate(dialogContext, "ls_settings_apn_hint"),
                    border: const OutlineInputBorder(),
                    errorText: _apnErrorText(dialogContext, problem),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (problem == null) {
                      Navigator.of(dialogContext).pop((clear: false, value: trimmed));
                    }
                  },
                ),
              ],
            ),
            actions: [
              if (_apn != null && _apn!.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop((clear: true, value: "")),
                  child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_clear")),
                ),
              TextButton(
                child: Text(FlutterI18n.translate(dialogContext, "cancel")),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.onSurface,
                  foregroundColor: Theme.of(dialogContext).colorScheme.surface,
                ),
                onPressed: problem == null
                    ? () => Navigator.of(dialogContext).pop((clear: false, value: trimmed))
                    : null,
                child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_save")),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted || !isCurrent()) return;

    setState(() => _isSendingApn = true);
    try {
      final service = context.read<ScooterService>();
      if (picked.clear) {
        await service.clearCellularApn();
      } else {
        await service.setCellularApn(picked.value);
      }
      if (!mounted || !isCurrent()) return;
      setState(() => _apn = picked.value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(
            context,
            picked.clear ? "ls_settings_apn_cleared" : "ls_settings_apn_success",
          )),
        ),
      );
    } catch (e) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_apn_error",
              translationParams: {"error": e.toString()})),
        ),
      );
    } finally {
      if (mounted && isCurrent()) setState(() => _isSendingApn = false);
    }
  }

  List<Widget> alarmItems() {
    if (_connected && context.watch<ScooterService>().identity.supportsAlarmControl != true) return [];
    final service = context.watch<ScooterService>();
    // The two switches ride the extended channel; everything else needs the
    // alarm service, which older firmware doesn't have.
    final bool live = service.alarmAvailable;
    final AlarmStatus? status = service.vehicle.alarmStatus;
    return [
      ListTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: Text(FlutterI18n.translate(context, "ls_settings_alarm_title")),
        subtitle: Text(_alarmSettingsLoaded && _alarmEnabled == null
            ? FlutterI18n.translate(context, "ls_settings_extended_unavailable")
            : live && status != null
            ? status.name(context)
            : FlutterI18n.translate(context, "ls_settings_alarm_subtitle")),
        trailing: !_alarmSettingsLoaded
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmEnabled ?? false,
                onChanged: _alarmEnabled == null || _isSendingAlarmEnabled ? null : _setAlarmEnabled,
              ),
      ),
      ListTile(
        leading: Icon(Icons.campaign_outlined),
        title: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_title")),
        subtitle: Text(FlutterI18n.translate(context, _alarmSettingsLoaded && _alarmHonk == null
            ? "ls_settings_extended_unavailable" : "ls_settings_alarm_honk_subtitle")),
        trailing: !_alarmSettingsLoaded
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmHonk ?? false,
                onChanged: _alarmHonk == null || _isSendingAlarmHonk ? null : _setAlarmHonk,
              ),
      ),
      if (live || !_connected)
        ListTile(
          leading: Icon(Icons.visibility_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_alarm_watch_title")),
          subtitle: Text(_alarmWatchSubtitle(context, service.vehicle)),
        ),
    ];
  }

  List<Widget> settingsItems() => [
        ListTile(
          leading: Icon(Icons.access_time_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_clock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_clock_subtitle")),
          trailing: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.onSurface,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: _isSendingTime
                  ? null
                  : () async {
                      if (!mounted || !_connected) return;
                      final isCurrent = _captureRequest();
                      setState(() => _isSendingTime = true);
                      try {
                        String? result = await context.read<ScooterService>().actions.setClock(DateTime.now()); // time:set expects seconds
                        if (!mounted || !isCurrent()) return;
                        if (result == "time:ok") {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(FlutterI18n.translate(context, "ls_settings_clock_success")),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(FlutterI18n.translate(context, "ls_settings_clock_error",
                                  translationParams: {"result": result ?? ""})),
                            ),
                          );
                        }
                      } finally {
                        if (context.mounted && isCurrent()) {
                          setState(() => _isSendingTime = false);
                        }
                      }
                    },
              child: _isSendingTime
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(FlutterI18n.translate(context, "ls_settings_clock_send"))),
        ),
        ListTile(
          leading: Icon(Icons.hourglass_bottom_rounded),
          title: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_subtitle")),
          trailing: DropdownButton<int>(
            value: _autoLockDuration,
            hint: Text(FlutterI18n.translate(context, "ls_settings_duration_hint")),
            items: [
              DropdownMenuItem(
                value: 0,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_never")),
              ),
              DropdownMenuItem(
                value: 180,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_min")),
              ),
              DropdownMenuItem(
                value: 300,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_5_min")),
              ),
              DropdownMenuItem(
                value: 600,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_10_min")),
              ),
            ],
            onChanged: _isSendingAutoLock
                ? null
                : (value) async {
                    if (!mounted || !_connected) return;
                    final isCurrent = _captureRequest();
                    if (value != null) {
                      try {
                        setState(() {
                          _isSendingAutoLock = true;
                        });
                        await context.read<ScooterService>().actions.setAutoStandbyTime(Duration(seconds: value),
                        );
                        if (!mounted || !isCurrent()) return;
                        setState(() {
                          _isSendingAutoLock = false;
                          _autoLockDuration = value;
                        });
                        if (!mounted || !isCurrent()) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_success")),
                          ),
                        );
                      } catch (e) {
                        if (!mounted || !isCurrent()) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              FlutterI18n.translate(
                                context,
                                "ls_settings_auto_lock_error",
                                translationParams: {"error": e.toString()},
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  },
          ),
        ),
        ListTile(
          leading: Icon(Icons.bedtime_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_subtitle")),
          trailing: DropdownButton<int>(
            hint: Text(FlutterI18n.translate(context, "ls_settings_duration_hint")),
            value: _autoHibernateDuration,
            items: [
              DropdownMenuItem(
                value: 3600,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_hour")),
              ),
              DropdownMenuItem(
                value: 86400,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_day")),
              ),
              DropdownMenuItem(
                value: 259200,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_days")),
              ),
              DropdownMenuItem(
                value: 604800,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_7_days")),
              ),
              DropdownMenuItem(
                value: 1209600,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_14_days")),
              ),
            ],
            onChanged: _isSendingAutoHibernate
                ? null
                : (value) async {
                    if (!mounted || !_connected) return;
                    final isCurrent = _captureRequest();
                    if (value != null) {
                      try {
                        setState(() {
                          _isSendingAutoHibernate = true;
                        });
                        await context.read<ScooterService>().actions.setAutoHibernateTime(Duration(seconds: value),
                        );
                        if (!mounted || !isCurrent()) return;
                        setState(() {
                          _isSendingAutoHibernate = false;
                          _autoHibernateDuration = value;
                        });
                        if (!mounted || !isCurrent()) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              FlutterI18n.translate(context, "ls_settings_auto_hibernate_success"),
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!mounted || !isCurrent()) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              FlutterI18n.translate(
                                context,
                                "ls_settings_auto_hibernate_error",
                                translationParams: {"error": e.toString()},
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  },
          ),
        ),
        if (!_connected || context.watch<ScooterService>().identity.supportsScheduledHibernation == true)
          ListTile(
            leading: Icon(Icons.bedtime_outlined),
            title: Text(FlutterI18n.translate(context, "ls_scheduled_hibernation_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_scheduled_hibernation_subtitle")),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => LsScheduledHibernationScreen()));
            },
          ),
        if (!_connected || context.watch<ScooterService>().identity.supportsApnConfig == true)
          ListTile(
            leading: Icon(Icons.cell_tower_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_apn_title")),
            subtitle: Text(_apnSubtitle(context)),
            trailing: _isSendingApn
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.chevron_right),
            onTap: _isSendingApn ? null : _editApn,
          ),
        ListTile(
          leading: Icon(Icons.usb_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_update_mode_title")),
          subtitle: Text(context.watch<ScooterService>().vehicle.usbMode == UsbMode.massStorage
              ? FlutterI18n.translate(context, "ls_settings_update_mode_on_subtitle")
              : FlutterI18n.translate(context, "ls_settings_update_mode_off_subtitle")),
          trailing: Switch(
            value: context.watch<ScooterService>().vehicle.usbMode == UsbMode.massStorage,
            onChanged: _isUpdatingUsbMode
                ? null
                : (value) async {
                    if (!mounted || !_connected) return;
                    final isCurrent = _captureRequest();
                    setState(() {
                      _isUpdatingUsbMode = true;
                    });

                    try {
                      if (value == true) {
                        await context.read<ScooterService>().actions.enterUMSMode();
                      } else {
                        await context.read<ScooterService>().actions.enterNormalUsbMode();
                      }
                      if (!mounted || !isCurrent()) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(FlutterI18n.translate(
                              context,
                              value
                                  ? "ls_settings_update_mode_enter_success"
                                  : "ls_settings_update_mode_exit_success")),
                        ),
                      );
                    } catch (e) {
                      if (!mounted || !isCurrent()) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(FlutterI18n.translate(context, "ls_settings_update_mode_error",
                              translationParams: {"error": e.toString()})),
                        ),
                      );
                    } finally {
                      if (mounted && isCurrent()) {
                        setState(() {
                          _isUpdatingUsbMode = false;
                        });
                      }
                    }
                  },
          ),
        ),
        if (!_connected || context.watch<ScooterService>().identity.supportsBatteryKeepActive == true)
          ListTile(
            leading: Icon(Icons.battery_charging_full_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_title")),
            subtitle: Text(FlutterI18n.translate(context, _batteryKeepActiveLoaded && _batteryKeepActive == null
                ? "ls_settings_extended_unavailable" : "ls_settings_battery_keep_active_subtitle")),
            trailing: !_batteryKeepActiveLoaded
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _batteryKeepActive ?? false,
                    onChanged: _batteryKeepActive == null || _isSendingBatteryKeepActive ? null : _setBatteryKeepActive,
                  ),
          ),
        ...alarmItems(),
        ListTile(
          leading: Icon(Icons.vpn_key_outlined),
          title: Text(FlutterI18n.translate(context, "ls_keycard_title")),
          subtitle: Text(!_keycardCountLoaded
              ? FlutterI18n.translate(context, "ls_settings_keycards_loading")
              : _keycardCount != null
                  ? FlutterI18n.translate(context, "ls_settings_keycards_count",
                      translationParams: {"count": _keycardCount.toString()})
                  : FlutterI18n.translate(context, "ls_settings_extended_unavailable")),
          trailing: _keycardCountLoaded && _keycardCount != null ? Icon(Icons.chevron_right) : null,
          onTap: _keycardCountLoaded && _keycardCount != null
              ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => LsKeycardScreen()))
              : null,
        ),
        if (!_connected || context.read<ScooterService>().otaAvailable)
          ListTile(
            leading: Icon(Icons.system_update_alt_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => LsOtaScreen()));
            },
          ),
        Container() // To force another divider after the last item
      ];

  @override
  Widget build(BuildContext context) {
    context.watch<ScooterService>();
    final items = _connectionRequiredItems(settingsItems());
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_settings_title")),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          itemBuilder: (context, index) => items[index],
        ),
      ),
    );
  }
}
