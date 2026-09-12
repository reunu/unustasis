import 'dart:async';
import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/theme_helper.dart';
import '../domain/alarm_status.dart';
import '../domain/scooter_keyless_distance.dart';
import '../scooter_service.dart';
import '../helper_widgets/header.dart';
import '../ls_keycard_screen.dart';
import '../ls_ota_screen.dart';
import '../ls_scheduled_hibernation_screen.dart';
import '../service/ble_commands.dart';
import '../state/vehicle_status.dart';
import 'log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final log = Logger('SettingsScreen');
  bool backgroundScan = false;
  bool biometrics = false;
  bool autoUnlock = false;
  bool seasonal = true;
  ScooterKeylessDistance autoUnlockDistance = ScooterKeylessDistance.regular;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;
  bool osmConsent = true;
  ScooterService? _service;
  Object? _sessionDevice;
  Object? _sessionRepository;
  bool _sessionConnected = false;
  int _session = 0;
  bool _lsDataLoadStarted = false;
  bool _batteryLoadStarted = false;
  bool _alarmLoadStarted = false;
  bool _isSendingBatteryKeepActive = false;
  bool? _batteryKeepActive;
  bool _isSendingAlarmEnabled = false;
  bool? _alarmEnabled;
  bool _isSendingAlarmHonk = false;
  bool? _alarmHonk;
  bool _isSendingAutoLock = false;
  int? _autoLockDuration;
  bool _timerDurationsLoaded = false;
  bool _isSendingAutoHibernate = false;
  int? _autoHibernateDuration;
  int? _keycardCount;
  bool _isSendingApn = false;
  bool _isUpdatingUsbMode = false;
  bool _apnLoaded = false;
  bool _apnLoadStarted = false;
  String? _apn;
  final TextEditingController _apnController = TextEditingController();
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();

  void getInitialSettings() async {
    ScooterService service = context.read<ScooterService>();
    bool initialBackgroundScan = await prefs.getBool("backgroundScan") ?? false;
    bool initialBiometrics = await prefs.getBool("biometrics") ?? false;
    bool initialAutoUnlock = service.autoUnlock;
    ScooterKeylessDistance initialAutoUnlockDistance =
        ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold) ?? ScooterKeylessDistance.regular.threshold;
    bool initialOpenSeatOnUnlock = service.openSeatOnUnlock;
    bool initialHazardLocking = service.hazardLocking;
    bool initialOsmConsent = await prefs.getBool("osmConsent") ?? true;
    bool initialSeasonal = await prefs.getBool("seasonal") ?? true;

    if (!mounted) return;
    setState(() {
      backgroundScan = initialBackgroundScan;
      biometrics = initialBiometrics;
      autoUnlock = initialAutoUnlock;
      autoUnlockDistance = initialAutoUnlockDistance;
      openSeatOnUnlock = initialOpenSeatOnUnlock;
      hazardLocking = initialHazardLocking;
      osmConsent = initialOsmConsent;
      seasonal = initialSeasonal;
    });
  }

  @override
  void initState() {
    super.initState();
    getInitialSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(service, _service)) return;
    _service?.removeListener(_onServiceChanged);
    _service = service;
    service.addListener(_onServiceChanged);
    _syncSession(force: true);
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() => _syncSession());
  }

  // Observe every notification, not only builds: disconnect/reconnect can both
  // happen before the next frame, even for the same device.
  void _syncSession({bool force = false}) {
    final service = _service!;
    final device = service.connected ? service.myScooter : null;
    final repository = service.connected ? service.characteristicRepository : null;
    if (!force &&
        _sessionConnected == service.connected &&
        identical(device, _sessionDevice) &&
        identical(repository, _sessionRepository)) {
      return;
    }
    _sessionConnected = service.connected;
    _sessionDevice = device;
    _sessionRepository = repository;
    _session++;
    _lsDataLoadStarted = _batteryLoadStarted = _alarmLoadStarted = false;
    _timerDurationsLoaded = _apnLoaded = _apnLoadStarted = false;
    _autoLockDuration = _autoHibernateDuration = _keycardCount = null;
    _apn = null;
    _batteryKeepActive = _alarmEnabled = _alarmHonk = null;
    _isSendingAutoLock = _isSendingAutoHibernate = _isSendingApn = false;
    _isUpdatingUsbMode = _isSendingBatteryKeepActive = false;
    _isSendingAlarmEnabled = _isSendingAlarmHonk = false;
  }

  bool _isCurrent(int session) =>
      mounted &&
      session == _session &&
      _service!.connected &&
      _sessionDevice != null &&
      identical(_service!.myScooter, _sessionDevice) &&
      identical(_service!.characteristicRepository, _sessionRepository);

  String _scooterScope() {
    final service = context.read<ScooterService>();
    if (service.connected) {
      final id = service.myScooter?.remoteId.toString();
      final name = service.savedScooters[id]?.name.trim();
      final label = name != null && name.isNotEmpty ? name : id;
      return FlutterI18n.translate(context, 'settings_scope_connected',
          translationParams: {'name': label ?? FlutterI18n.translate(context, 'settings_scope_unknown')});
    }
    final name = service.identity.name?.trim();
    return name != null && name.isNotEmpty
        ? FlutterI18n.translate(context, 'settings_scope_cached', translationParams: {'name': name})
        : FlutterI18n.translate(context, 'settings_scope_unknown');
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    _apnController.dispose();
    super.dispose();
  }

  bool get _scooterConnected => context.read<ScooterService>().connected;

  // Keep scooter controls discoverable offline without building loading or
  // actionable children. App-local preferences and cached diagnostics stay usable.
  List<Widget> _connectionRequiredItems(List<Widget> items) {
    if (_scooterConnected) return items;
    return items.map((item) {
      Widget? leading;
      Widget? title;
      if (item is ListTile) {
        leading = item.leading;
        title = item.title;
      } else {
        return item;
      }
      return ListTile(
        enabled: false,
        leading: leading,
        title: title,
        subtitle: Text(FlutterI18n.translate(context, 'settings_scooter_disconnected')),
        trailing: const Icon(Icons.bluetooth_disabled),
      );
    }).toList();
  }

  void _ensureLsDataLoaded(bool isLibrescoot) {
    final service = context.read<ScooterService>();
    if (!isLibrescoot || !_isCurrent(_session)) return;
    final session = _session;
    if (!_lsDataLoadStarted) {
      _lsDataLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isCurrent(session)) return;
        _getKeycardCount();
        _getTimerDurations();
      });
    }
    if (service.identity.supportsApnConfig == true && !_apnLoaded && !_apnLoadStarted) {
      _apnLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrent(session)) _getApn();
      });
    }
    if (service.identity.supportsBatteryKeepActive == true && !_batteryLoadStarted) {
      _batteryLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrent(session)) _getBatteryKeepActive();
      });
    }
    if (service.identity.supportsAlarmControl == true && !_alarmLoadStarted) {
      _alarmLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrent(session)) _getAlarmSettings();
      });
    }
  }

  Future<void> _getKeycardCount() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    try {
      final count = await countKeycardsCommand(_service!.myScooter, _service!.characteristicRepository);
      if (_isCurrent(session)) setState(() => _keycardCount = count);
    } catch (_) {}
  }

  Future<void> _getTimerDurations() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    try {
      final service = _service!;
      final values = await Future.wait([
        getLsSettingCommand(service.myScooter, service.characteristicRepository, lsKeyAutoStandbySeconds),
        getLsSettingCommand(service.myScooter, service.characteristicRepository, lsKeyHibernateTimer),
      ]);
      if (!mounted || !_isCurrent(session)) return;
      setState(() {
        _autoLockDuration = int.tryParse(values[0] ?? "");
        _autoHibernateDuration = int.tryParse(values[1] ?? "");
        _timerDurationsLoaded = true;
      });
    } catch (_) {
      if (_isCurrent(session)) setState(() => _timerDurationsLoaded = true);
    }
  }

  Widget _timerLoadingIndicator() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Future<void> _getApn() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    String? apn;
    try {
      apn = await context.read<ScooterService>().getCellularApn();
    } catch (_) {}
    if (mounted && _isCurrent(session)) {
      setState(() {
        _apn = apn;
        _apnLoaded = true;
      });
    }
  }

  Future<void> _getBatteryKeepActive() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    bool? enabled;
    try {
      enabled = await context.read<ScooterService>().getBatteryKeepActive();
    } catch (e) {
      enabled = null;
    }
    if (!mounted || !_isCurrent(session)) return;
    setState(() {
      _batteryKeepActive = enabled;
    });
  }

  Future<void> _setBatteryKeepActive(bool enabled) async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    setState(() {
      _isSendingBatteryKeepActive = true;
    });
    try {
      await context.read<ScooterService>().setBatteryKeepActive(enabled);
      if (!mounted || !_isCurrent(session)) return;
      setState(() {
        _batteryKeepActive = enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context,
              enabled ? "ls_settings_battery_keep_active_on_success" : "ls_settings_battery_keep_active_off_success")),
        ),
      );
    } catch (e) {
      if (!mounted || !_isCurrent(session)) return;
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
      if (mounted && _isCurrent(session)) {
        setState(() {
          _isSendingBatteryKeepActive = false;
        });
      }
    }
  }

  Future<void> _getAlarmSettings() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    bool? enabled;
    bool? honk;
    try {
      final service = context.read<ScooterService>();
      enabled = await service.getAlarmEnabled();
      if (!mounted || !_isCurrent(session)) return;
      honk = await service.getAlarmHonk();
    } catch (e) {
      enabled = null;
      honk = null;
    }
    if (!mounted || !_isCurrent(session)) return;
    setState(() {
      _alarmEnabled = enabled;
      _alarmHonk = honk;
    });
  }

  Future<void> _setAlarmEnabled(bool enabled) async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    setState(() {
      _isSendingAlarmEnabled = true;
    });
    try {
      await context.read<ScooterService>().setAlarmEnabled(enabled);
      if (!mounted || !_isCurrent(session)) return;
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
      if (!mounted || !_isCurrent(session)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              FlutterI18n.translate(context, "ls_settings_alarm_error", translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted && _isCurrent(session)) {
        setState(() {
          _isSendingAlarmEnabled = false;
        });
      }
    }
  }

  Future<void> _setAlarmHonk(bool enabled) async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    setState(() {
      _isSendingAlarmHonk = true;
    });
    try {
      await context.read<ScooterService>().setAlarmHonk(enabled);
      if (!mounted || !_isCurrent(session)) return;
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
      if (!mounted || !_isCurrent(session)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_error",
              translationParams: {"error": e.toString()})),
        ),
      );
      unawaited(_getAlarmSettings());
    } finally {
      if (mounted && _isCurrent(session)) {
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

  Widget _lsTitle(String title) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title)),
          const SizedBox(width: 6),
          const Icon(Icons.local_fire_department_outlined, size: 16),
        ],
      );

  String _apnSubtitle(BuildContext context) {
    if (!_apnLoaded) return FlutterI18n.translate(context, "ls_settings_apn_loading");
    if (_apn == null) return FlutterI18n.translate(context, "ls_settings_apn_unknown");
    return _apn!.isEmpty ? FlutterI18n.translate(context, "ls_settings_apn_unset") : _apn!;
  }

  String? _apnErrorText(BuildContext context, ApnProblem? problem) {
    switch (problem) {
      case null:
      case ApnProblem.empty:
        return null;
      case ApnProblem.invalidCharacters:
        return FlutterI18n.translate(context, "ls_settings_apn_invalid_chars");
      case ApnProblem.tooLong:
        return FlutterI18n.translate(
          context,
          "ls_settings_apn_invalid_length",
          translationParams: {"max": maxApnLength.toString()},
        );
    }
  }

  Future<void> _editApn() async {
    final session = _session;
    if (!mounted || !_isCurrent(session)) return;
    final controller = _apnController..text = _apn ?? "";
    final picked = await showDialog<({bool clear, String value})>(
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
                    if (problem == null) Navigator.of(dialogContext).pop((clear: false, value: trimmed));
                  },
                ),
              ],
            ),
            actions: [
              if (_apn != null && _apn!.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
                  onPressed: () => Navigator.of(dialogContext).pop((clear: true, value: "")),
                  child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_clear")),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(FlutterI18n.translate(dialogContext, "cancel")),
              ),
              FilledButton(
                onPressed:
                    problem == null ? () => Navigator.of(dialogContext).pop((clear: false, value: trimmed)) : null,
                child: Text(FlutterI18n.translate(dialogContext, "ls_settings_apn_save")),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted || !_isCurrent(session)) return;

    setState(() => _isSendingApn = true);
    try {
      final service = context.read<ScooterService>();
      if (picked.clear) {
        await service.clearCellularApn();
      } else {
        await service.setCellularApn(picked.value);
      }
      if (!mounted || !_isCurrent(session)) return;
      setState(() => _apn = picked.value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          picked.clear ? "ls_settings_apn_cleared" : "ls_settings_apn_success",
        ))),
      );
    } catch (e) {
      if (!mounted || !_isCurrent(session)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          "ls_settings_apn_error",
          translationParams: {"error": e.toString()},
        ))),
      );
    } finally {
      if (_isCurrent(session)) setState(() => _isSendingApn = false);
    }
  }

  List<Widget> alarmItems() {
    if (_scooterConnected && context.read<ScooterService>().identity.supportsAlarmControl != true) return [];
    final service = context.read<ScooterService>();
    // The two switches ride the extended channel; everything else needs the
    // alarm service, which older firmware doesn't have.
    final bool live = service.connected && service.characteristicRepository.alarmAvailable;
    final AlarmStatus? status = service.vehicle.alarmStatus;
    return [
      ListTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_title")),
        subtitle: Text(live && status != null
            ? status.name(context)
            : FlutterI18n.translate(context, "ls_settings_alarm_subtitle")),
        trailing: _alarmEnabled == null
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmEnabled!,
                onChanged: _isSendingAlarmEnabled ? null : _setAlarmEnabled,
              ),
      ),
      ListTile(
        leading: Icon(Icons.campaign_outlined),
        title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_honk_title")),
        subtitle: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_honk_subtitle")),
        trailing: _alarmHonk == null
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Switch(
                value: _alarmHonk!,
                onChanged: _isSendingAlarmHonk ? null : _setAlarmHonk,
              ),
      ),
      if (!service.connected || live)
        ListTile(
          leading: Icon(Icons.visibility_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_watch_title")),
          subtitle: Text(_alarmWatchSubtitle(context, service.vehicle)),
        ),
    ];
  }

  List<Widget> _librescootScooterSettingsItems({required bool supportsScheduledHibernation}) => [
        if (!_scooterConnected || context.read<ScooterService>().identity.supportsBatteryKeepActive == true)
          ListTile(
            leading: Icon(Icons.battery_charging_full_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_battery_keep_active_title")),
            subtitle: _lsTitle(FlutterI18n.translate(context, "ls_settings_battery_keep_active_subtitle")),
            trailing: _batteryKeepActive == null
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _batteryKeepActive!,
                    onChanged: _isSendingBatteryKeepActive ? null : _setBatteryKeepActive,
                  ),
          ),
        ...alarmItems(),
        ListTile(
          leading: const Icon(Icons.hourglass_bottom_rounded),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_auto_lock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoLockDuration,
              hint: _timerDurationsLoaded
                  ? Text(FlutterI18n.translate(context, "ls_settings_duration_hint"))
                  : _timerLoadingIndicator(),
              items: [
                if (_autoLockDuration != null && ![0, 180, 300, 600, 900].contains(_autoLockDuration))
                  DropdownMenuItem(value: _autoLockDuration, child: Text('${_autoLockDuration}s')),
                DropdownMenuItem(value: 0, child: Text(FlutterI18n.translate(context, "ls_settings_duration_never"))),
                DropdownMenuItem(value: 180, child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_min"))),
                DropdownMenuItem(value: 300, child: Text(FlutterI18n.translate(context, "ls_settings_duration_5_min"))),
                DropdownMenuItem(
                    value: 600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_10_min"))),
                DropdownMenuItem(
                    value: 900, child: Text(FlutterI18n.translate(context, "ls_settings_duration_15_min"))),
              ],
              onChanged: !_timerDurationsLoaded || _isSendingAutoLock
                  ? null
                  : (value) async {
                      final session = _session;
                      if (value == null || !_isCurrent(session)) return;
                      setState(() => _isSendingAutoLock = true);
                      try {
                        await setAutoStandbyTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        if (!mounted || !_isCurrent(session)) return;
                        setState(() => _autoLockDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_success"))),
                        );
                      } catch (e) {
                        if (mounted && _isCurrent(session)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(FlutterI18n.translate(
                              context,
                              "ls_settings_auto_lock_error",
                              translationParams: {"error": e.toString()},
                            ))),
                          );
                        }
                      } finally {
                        if (_isCurrent(session)) setState(() => _isSendingAutoLock = false);
                      }
                    },
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_auto_hibernate_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoHibernateDuration,
              hint: _timerDurationsLoaded
                  ? Text(FlutterI18n.translate(context, "ls_settings_duration_hint"))
                  : _timerLoadingIndicator(),
              items: [
                if (_autoHibernateDuration != null &&
                    ![0, 3600, 86400, 259200, 604800, 1209600].contains(_autoHibernateDuration))
                  DropdownMenuItem(value: _autoHibernateDuration, child: Text('${_autoHibernateDuration}s')),
                DropdownMenuItem(value: 0, child: Text(FlutterI18n.translate(context, "ls_settings_duration_never"))),
                DropdownMenuItem(
                    value: 3600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_hour"))),
                DropdownMenuItem(
                    value: 86400, child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_day"))),
                DropdownMenuItem(
                    value: 259200, child: Text(FlutterI18n.translate(context, "ls_settings_duration_3_days"))),
                DropdownMenuItem(
                    value: 604800, child: Text(FlutterI18n.translate(context, "ls_settings_duration_7_days"))),
                DropdownMenuItem(
                    value: 1209600, child: Text(FlutterI18n.translate(context, "ls_settings_duration_14_days"))),
              ],
              onChanged: !_timerDurationsLoaded || _isSendingAutoHibernate
                  ? null
                  : (value) async {
                      final session = _session;
                      if (value == null || !_isCurrent(session)) return;
                      setState(() => _isSendingAutoHibernate = true);
                      try {
                        await setAutoHibernateTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        if (!mounted || !_isCurrent(session)) return;
                        setState(() => _autoHibernateDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_success"))),
                        );
                      } catch (e) {
                        if (mounted && _isCurrent(session)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(FlutterI18n.translate(
                              context,
                              "ls_settings_auto_hibernate_error",
                              translationParams: {"error": e.toString()},
                            ))),
                          );
                        }
                      } finally {
                        if (_isCurrent(session)) setState(() => _isSendingAutoHibernate = false);
                      }
                    },
            ),
          ),
        ),
        if (!_scooterConnected || supportsScheduledHibernation)
          ListTile(
            leading: const SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                children: [
                  Positioned(left: 0, top: 0, child: Icon(Icons.bedtime_outlined, size: 22)),
                  Positioned(right: 0, top: 0, child: Icon(Icons.access_time_filled, size: 12)),
                ],
              ),
            ),
            title: _lsTitle(FlutterI18n.translate(context, "ls_scheduled_hibernation_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_scheduled_hibernation_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LsScheduledHibernationScreen()),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_keycard_title")),
          subtitle: Text(_keycardCount != null
              ? FlutterI18n.translate(context, "ls_settings_keycards_count",
                  translationParams: {"count": _keycardCount.toString()})
              : FlutterI18n.translate(context, "ls_settings_keycards_loading")),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsKeycardScreen())),
        ),
      ];

  List<Widget> _librescootMaintenanceSettingsItems({
    required bool supportsApnConfig,
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        if (!connected || otaAvailable)
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsOtaScreen())),
          ),
        ListTile(
          leading: const Icon(Icons.usb_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_update_mode_title")),
          subtitle: Text(usbMode == UsbMode.massStorage
              ? FlutterI18n.translate(context, "ls_settings_update_mode_on_subtitle")
              : FlutterI18n.translate(context, "ls_settings_update_mode_off_subtitle")),
          trailing: Switch(
            value: usbMode == UsbMode.massStorage,
            onChanged: _isUpdatingUsbMode
                ? null
                : (value) async {
                    final session = _session;
                    if (!mounted || !_isCurrent(session)) return;
                    setState(() => _isUpdatingUsbMode = true);
                    try {
                      final service = context.read<ScooterService>();
                      if (value) {
                        await enterUMSModeCommand(service.myScooter, service.characteristicRepository);
                      } else {
                        await enterNormalUsbModeCommand(service.myScooter, service.characteristicRepository);
                      }
                      if (!mounted || !_isCurrent(session)) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(FlutterI18n.translate(
                          context,
                          value ? "ls_settings_update_mode_enter_success" : "ls_settings_update_mode_exit_success",
                        ))),
                      );
                    } catch (e) {
                      if (mounted && _isCurrent(session)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(FlutterI18n.translate(
                            context,
                            "ls_settings_update_mode_error",
                            translationParams: {"error": e.toString()},
                          ))),
                        );
                      }
                    } finally {
                      if (_isCurrent(session)) setState(() => _isUpdatingUsbMode = false);
                    }
                  },
          ),
        ),
        if (!_scooterConnected || supportsApnConfig)
          ListTile(
            leading: const Icon(Icons.cell_tower_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_apn_title")),
            subtitle: Text(_apnSubtitle(context)),
            trailing: _isSendingApn
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isSendingApn ? null : _editApn,
          ),
      ];

  List<Widget> settingsItems({
    required bool isLibrescoot,
    required bool supportsScheduledHibernation,
    required bool supportsApnConfig,
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        Header(
          FlutterI18n.translate(context, "stats_settings_section_scooter"),
          subtitle: _scooterScope(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        ),
        if (isLibrescoot)
          ..._connectionRequiredItems(
              _librescootScooterSettingsItems(supportsScheduledHibernation: supportsScheduledHibernation)),
        if (isLibrescoot) ...[
          Header(FlutterI18n.translate(context, "ls_settings_section_maintenance"), subtitle: _scooterScope()),
          ..._connectionRequiredItems(_librescootMaintenanceSettingsItems(
            supportsApnConfig: supportsApnConfig,
            usbMode: usbMode,
            connected: connected,
            otaAvailable: otaAvailable,
          )),
        ],
        Header(FlutterI18n.translate(context, "stats_settings_section_app"),
            subtitle: FlutterI18n.translate(context, 'settings_scope_app')),
        SwitchListTile(
          secondary: const Icon(Icons.lock_open),
          title: Text(FlutterI18n.translate(context, "settings_auto_unlock")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_auto_unlock_description"),
          ),
          value: autoUnlock,
          onChanged: (value) async {
            if (value == true) {
              // Check location permission (required for Bluetooth proximity detection)
              bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_services_disabled"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }

              LocationPermission permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.denied) {
                permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.denied && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "location_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }
              }

              if (permission == LocationPermission.deniedForever && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_permission_denied_forever"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }
            }

            if (!mounted) return;

            context.read<ScooterService>().setAutoUnlock(value);
            setState(() {
              autoUnlock = value;
            });
          },
        ),
        if (autoUnlock)
          ListTile(
            title: Text(
              "${FlutterI18n.translate(context, "settings_auto_unlock_threshold")}: ${autoUnlockDistance.name(context)}",
            ),
            subtitle: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: autoUnlockDistance.threshold.toDouble(),
                  min: ScooterKeylessDistance.getMinThresholdDistance().threshold.toDouble(),
                  max: ScooterKeylessDistance.getMaxThresholdDistance().threshold.toDouble(),
                  secondaryTrackValue: context.read<ScooterService>().identity.rssi?.toDouble(),
                  divisions: ScooterKeylessDistance.values.length - 1,
                  label: autoUnlockDistance.getFormattedThreshold(),
                  onChanged: (value) async {
                    var distance = ScooterKeylessDistance.fromThreshold(
                      value.toInt(),
                    );
                    context.read<ScooterService>().setAutoUnlockThreshold(
                          value.toInt(),
                        );
                    setState(() {
                      autoUnlockDistance = distance;
                    });
                  },
                ),
                if (context.read<ScooterService>().identity.rssi != null)
                  Text(
                    FlutterI18n.translate(
                      context,
                      "settings_auto_unlock_threshold_explainer",
                      translationParams: {
                        "rssi": context.read<ScooterService>().identity.rssi.toString(),
                      },
                    ),
                  ),
              ],
            ),
          ),
        SwitchListTile(
          secondary: SvgPicture.asset(
            "assets/icons/librescoot-seatbox-open.svg",
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              BlendMode.srcIn,
            ),
          ),
          title: Text(
            FlutterI18n.translate(context, "settings_open_seat_on_unlock"),
          ),
          subtitle: Text(
            FlutterI18n.translate(
              context,
              "settings_open_seat_on_unlock_description",
            ),
          ),
          value: openSeatOnUnlock,
          onChanged: (value) async {
            context.read<ScooterService>().setOpenSeatOnUnlock(value);
            setState(() {
              openSeatOnUnlock = value;
            });
          },
        ),
        SwitchListTile(
          secondary: const ImageIcon(
            AssetImage("assets/icons/librescoot-blinkers.png"),
            size: 24,
          ),
          title: Text(FlutterI18n.translate(context, "settings_hazard_locking")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_hazard_locking_description"),
          ),
          value: hazardLocking,
          onChanged: (value) async {
            context.read<ScooterService>().setHazardLocking(value);
            setState(() {
              hazardLocking = value;
            });
          },
        ),
        if (kDebugMode)
          ListTile(
            title: Text(FlutterI18n.translate(context, "activity_log_title")),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogScreen(),
                ),
              );
            },
            leading: const Icon(Icons.history_outlined),
            trailing: const Icon(Icons.chevron_right),
          ),

        if (Platform.isAndroid)
          SwitchListTile(
            secondary: const Icon(Icons.find_replace_outlined),
            title: Text(FlutterI18n.translate(context, "settings_background_scan")),
            subtitle: Text(
              FlutterI18n.translate(
                context,
                "settings_background_scan_description",
              ),
            ),
            value: backgroundScan,
            onChanged: (value) async {
              bool? confirmed;
              if (value == true) {
                // Request notification permission first
                final notificationPlugin = FlutterLocalNotificationsPlugin();
                final granted = await notificationPlugin
                    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                    ?.requestNotificationsPermission();

                if (granted != true && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "notification_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }

                // warn before turning on
                if (mounted) {
                  confirmed = await showBackgroundScanWarning(context);
                }
              } else {
                // no warning for turning off
                confirmed = true;
              }
              if (confirmed == true) {
                await prefs.setBool("backgroundScan", value);
                // inform the service!
                FlutterBackgroundService().invoke("update", {
                  "backgroundScan": value,
                });
                if (!mounted) return;
                setState(() {
                  backgroundScan = value;
                });
              }
            },
          ),
        FutureBuilder<List<BiometricType>>(
          future: LocalAuthentication().getAvailableBiometrics(),
          builder: (context, biometricsOptionsSnap) {
            if (biometricsOptionsSnap.hasData && biometricsOptionsSnap.data!.isNotEmpty) {
              return SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text(FlutterI18n.translate(context, "settings_biometrics")),
                subtitle: Text(
                  FlutterI18n.translate(context, "settings_biometrics_description"),
                ),
                value: biometrics,
                onChanged: (value) async {
                  final LocalAuthentication auth = LocalAuthentication();
                  try {
                    final bool didAuthenticate = await auth.authenticate(
                      localizedReason: FlutterI18n.translate(
                        context,
                        "biometrics_message",
                      ),
                    );
                    if (didAuthenticate) {
                      await prefs.setBool("biometrics", value);
                      if (!mounted) return;
                      setState(() {
                        biometrics = value;
                      });
                    } else {
                      if (context.mounted) {
                        Fluttertoast.showToast(
                          msg: FlutterI18n.translate(context, "biometrics_failed"),
                        );
                      }
                    }
                  } catch (e, stack) {
                    if (context.mounted) {
                      log.warning("Biometrics error", e, stack);
                      Fluttertoast.showToast(
                        msg: FlutterI18n.translate(context, "biometrics_failed"),
                      );
                    }
                  }
                },
              );
            } else {
              return Container();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: Text(FlutterI18n.translate(context, "settings_theme")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: SegmentedButton<ThemeMode>(
              onSelectionChanged: (newTheme) {
                context.setThemeMode(newTheme.first);
              },
              showSelectedIcon: false,
              selected: {EasyDynamicTheme.of(context).themeMode!},
              style: ButtonStyle(
                iconColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.onTertiary;
                  }
                  return Theme.of(context).colorScheme.onSurface;
                }),
                backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.primary;
                  }
                  return Colors.transparent;
                }),
              ),
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.light
                        ? Icons.light_mode
                        : Icons.light_mode_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_light"),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.dark
                        ? Icons.nights_stay
                        : Icons.nights_stay_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_dark"),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.system
                        ? Icons.brightness_auto
                        : Icons.brightness_auto_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_system"),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(FlutterI18n.translate(context, "settings_language")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<Locale>(
              initialValue: FlutterI18n.currentLocale(context)!,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(16),
                border: OutlineInputBorder(),
              ),
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              items: [
                DropdownMenuItem<Locale>(
                  value: const Locale("en"),
                  child: Text(FlutterI18n.translate(context, "language_en")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("en", "GB"),
                  child: Text(FlutterI18n.translate(context, "language_en_gb")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("de"),
                  child: Text(FlutterI18n.translate(context, "language_de")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("fr"),
                  child: Text(FlutterI18n.translate(context, "language_fr")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("nl"),
                  child: Text(FlutterI18n.translate(context, "language_nl")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("pi"),
                  child: Text(FlutterI18n.translate(context, "language_pi")),
                ),
              ],
              onChanged: (Locale? newLanguage) async {
                await FlutterI18n.refresh(context, newLanguage);
                final tag = newLanguage!.countryCode != null
                    ? '${newLanguage.languageCode}_${newLanguage.countryCode}'
                    : newLanguage.languageCode;
                await prefs.setString("savedLocale", tag);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pin_drop_outlined),
          title: Text(FlutterI18n.translate(context, "settings_osm_consent")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_osm_consent_description"),
          ),
          value: osmConsent,
          onChanged: (value) async {
            await prefs.setBool("osmConsent", value);
            if (!mounted) return;
            setState(() {
              osmConsent = value;
            });
          },
        ),
        if (DateTime.now().month == 12 ||
            DateTime.now().month == 4 ||
            DateTime.now().month == 10) // All seasonal months
          SwitchListTile(
            secondary: const Icon(Icons.star),
            title: Text(FlutterI18n.translate(context, "settings_seasonal")),
            subtitle: Text(FlutterI18n.translate(context, "settings_color_info")),
            value: seasonal,
            onChanged: (value) async {
              await prefs.setBool("seasonal", value);
              if (!mounted) return;
              setState(() {
                seasonal = value;
              });
            },
          ),
        Container(), // to force another divider at the end
      ];

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final ls = (
      isLibrescoot: service.identity.isLibrescoot == true,
      supportsScheduled: service.identity.supportsScheduledHibernation == true,
      supportsApn: service.identity.supportsApnConfig == true,
      usbMode: service.vehicle.usbMode,
      connected: service.connected,
      otaAvailable: service.connected && service.characteristicRepository.otaAvailable,
    );
    _ensureLsDataLoaded(ls.isLibrescoot);
    final items = settingsItems(
      isLibrescoot: ls.isLibrescoot,
      supportsScheduledHibernation: ls.supportsScheduled,
      supportsApnConfig: ls.supportsApn,
      usbMode: ls.usbMode,
      connected: ls.connected,
      otaAvailable: ls.otaAvailable,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_settings')),
        backgroundColor: Theme.of(context).colorScheme.surface,
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

  Future<bool?> showBackgroundScanWarning(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            FlutterI18n.translate(context, "bgscan_warning_title"),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FlutterI18n.translate(context, "bgscan_warning_intro"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.battery_alert_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_battery"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(child: Icon(Icons.link_off_outlined, size: 32)),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_lostpairing"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.power_settings_new_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(
                  context,
                  "bgscan_warning_accidentalturnon",
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                FlutterI18n.translate(context, "forget_alert_cancel"),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                FlutterI18n.translate(context, "bgscan_warning_confirm"),
              ),
            ),
          ],
        );
      },
    );
  }
}
