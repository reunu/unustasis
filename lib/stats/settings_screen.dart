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
import '../domain/saved_scooter.dart';
import '../domain/scooter_keyless_distance.dart';
import '../domain/scooter_state.dart';
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
  bool _sessionAsleep = false;
  int _session = 0;
  bool _lsDataLoadStarted = false;
  // Keycard count: one read, retried on later notifications, bounded.
  // bounded so a scooter that never answers can't loop.
  static const int _maxKeycardLoadAttempts = 3;
  int _keycardLoadAttempts = 0;
  bool _keycardLoadInFlight = false;
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

  // Every notification, not only builds: reconnect can beat the next frame.
  void _syncSession({bool force = false}) {
    final service = _service!;
    final device = service.connected ? service.myScooter : null;
    final repository = service.connected ? service.characteristicRepository : null;
    final bool asleep = _scooterAsleep;
    if (!force &&
        _sessionConnected == service.connected &&
        identical(device, _sessionDevice) &&
        identical(repository, _sessionRepository) &&
        _sessionAsleep == asleep) {
      return;
    }
    // Same scooter falling asleep keeps the values we read; waking reloads them.
    // can have changed anything while it slept.
    final bool sameLink = !force &&
        _sessionConnected == service.connected &&
        identical(device, _sessionDevice) &&
        identical(repository, _sessionRepository);
    final bool waking = _sessionAsleep && !asleep;
    _sessionAsleep = asleep;
    _sessionConnected = service.connected;
    _sessionDevice = device;
    _sessionRepository = repository;
    _session++;
    if (sameLink && !waking) return;
    _lsDataLoadStarted = _batteryLoadStarted = _alarmLoadStarted = false;
    _timerDurationsLoaded = _apnLoaded = _apnLoadStarted = false;
    _autoLockDuration = _autoHibernateDuration = _keycardCount = null;
    _keycardLoadAttempts = 0;
    _keycardLoadInFlight = false;
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

  String _scooterScopeOnly() {
    final service = context.read<ScooterService>();
    final String? label;
    if (service.connected) {
      final id = service.myScooter?.remoteId.toString();
      final name = service.savedScooters[id]?.name.trim();
      label = name != null && name.isNotEmpty ? name : id;
    } else {
      final name = service.identity.name?.trim();
      label = name != null && name.isNotEmpty ? name : null;
    }
    return label == null
        ? FlutterI18n.translate(context, 'settings_scope_unknown')
        : FlutterI18n.translate(context, 'settings_scope_scooter_only', translationParams: {'name': label});
  }

  // Connected id, else cached name, else the only saved scooter.
  SavedScooter? _currentSavedScooter() {
    final service = context.read<ScooterService>();
    if (service.connected) {
      final id = service.myScooter?.remoteId.toString();
      final scooter = service.savedScooters[id];
      if (scooter != null) return scooter;
    }
    final name = service.identity.name?.trim();
    if (name != null && name.isNotEmpty) {
      for (final scooter in service.savedScooters.values) {
        if (scooter.name.trim() == name) return scooter;
      }
    }
    if (service.savedScooters.length == 1) return service.savedScooters.values.first;
    return null;
  }

  // Also in the scooter list, reachable there only by long-press.
  List<Widget> _scooterAutoConnectItems() {
    final savedScooter = _currentSavedScooter();
    if (savedScooter == null) return const [];
    return [
      SwitchListTile(
        secondary: const Icon(Icons.sync),
        title: Text(FlutterI18n.translate(context, "settings_scooter_auto_connect")),
        subtitle: Text(FlutterI18n.translate(context, "settings_scooter_auto_connect_description")),
        value: savedScooter.autoConnect,
        onChanged: (value) => setState(() => savedScooter.autoConnect = value),
      ),
    ];
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    _apnController.dispose();
    super.dispose();
  }

  bool get _scooterConnected => context.read<ScooterService>().connected;

  // Offline: keep controls visible but inert.
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

  // Hibernating scooters hold the link but never answer extended reads.
  bool get _scooterAsleep {
    switch (_service?.state) {
      case ScooterState.hibernating:
      case ScooterState.hibernatingImminent:
      case ScooterState.booting:
        return true;
      default:
        return false;
    }
  }

  List<Widget> _asleepAwareItems(List<Widget> items) =>
      _scooterAsleep ? items : _connectionRequiredItems(items);

  // A dash, not "off": we cannot claim a state we could not read.
  Widget _asleepValuePlaceholder() =>
      Text('—', style: TextStyle(color: Theme.of(context).disabledColor));

  // Unknown is not absence: keep the group visible while asleep.
  bool _alarmSectionVisible(ScooterService service) {
    if (!_scooterAsleep) return service.identity.supportsAlarmControl == true;
    return service.identity.supportsAlarmControl != false;
  }

  void _ensureLsDataLoaded(bool isLibrescoot) {
    final service = context.read<ScooterService>();
    if (!isLibrescoot || !_isCurrent(_session) || _scooterAsleep) return;
    final session = _session;
    if (!_lsDataLoadStarted) {
      _lsDataLoadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isCurrent(session)) return;
        _getTimerDurations();
      });
    }
    _loadKeycards(session);
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

  void _loadKeycards(int session) {
    if (_keycardCount != null ||
        _keycardLoadInFlight ||
        _keycardLoadAttempts >= _maxKeycardLoadAttempts) {
      return;
    }
    _keycardLoadAttempts++;
    _keycardLoadInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted && _isCurrent(session)) await _getKeycardCount(session);
      } finally {
        _keycardLoadInFlight = false;
      }
    });
  }

  Future<void> _getKeycardCount(int session) async {
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
      // Re-read: the scooter kept its old value.
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

  // Would it notice movement now, plus wake timer and last trigger.
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
      return FlutterI18n.translate(
          context, _scooterAsleep ? "ls_settings_scooter_asleep" : "ls_settings_alarm_watch_loading");
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
    if (!_apnLoaded) {
      return FlutterI18n.translate(
          context, _scooterAsleep ? "ls_settings_scooter_asleep" : "ls_settings_apn_loading");
    }
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
    final service = context.read<ScooterService>();
    if (_scooterConnected && !_alarmSectionVisible(service)) return [];
    // Switches ride the extended channel; the rest needs the alarm service.
    final bool live = service.connected && service.characteristicRepository.alarmAvailable;
    final AlarmStatus? status = service.vehicle.alarmStatus;
    return [
      ListTile(
        enabled: !_scooterAsleep,
        leading: Icon(Icons.notifications_active_outlined),
        title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_title")),
        subtitle: Text(live && status != null
            ? status.name(context)
            : FlutterI18n.translate(context, "ls_settings_alarm_subtitle")),
        trailing: _alarmEnabled == null
            ? (_scooterAsleep
                ? _asleepValuePlaceholder()
                : const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
            : Switch(
                value: _alarmEnabled!,
                onChanged: _isSendingAlarmEnabled || _scooterAsleep ? null : _setAlarmEnabled,
              ),
      ),
      ListTile(
        enabled: !_scooterAsleep,
        leading: Icon(Icons.campaign_outlined),
        title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_honk_title")),
        subtitle: Text(FlutterI18n.translate(context, "ls_settings_alarm_honk_subtitle")),
        trailing: _alarmHonk == null
            ? (_scooterAsleep
                ? _asleepValuePlaceholder()
                : const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
            : Switch(
                value: _alarmHonk!,
                onChanged: _isSendingAlarmHonk || _scooterAsleep ? null : _setAlarmHonk,
              ),
      ),
      if (!service.connected || live)
        ListTile(
          enabled: !_scooterAsleep,
          leading: Icon(Icons.visibility_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_alarm_watch_title")),
          subtitle: Text(_alarmWatchSubtitle(context, service.vehicle)),
        ),
    ];
  }

  // Shared by all scooters, so it lives under App.
  List<Widget> _automationItems() => [
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
      ];

  List<Widget> _backgroundConnectionItems() => [
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
      ];

  List<Widget> _biometricsItems() => [
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
      ];

  List<Widget> _themeItems() => [
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
      ];

  List<Widget> _languageItems() => [
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
      ];

  List<Widget> _locationConsentItems() => [
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
      ];

  List<Widget> _seasonalItems() => [
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
      ];

  List<Widget> _activityLogItems() => [
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
      ];

  List<Widget> _accessItems({required bool isLibrescoot}) => [
        if (isLibrescoot)
          ListTile(
            enabled: !_scooterAsleep,
            leading: const Icon(Icons.vpn_key_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_keycard_title")),
            subtitle: Text(_keycardCount != null
                ? FlutterI18n.translate(context, "ls_settings_keycards_count",
                    translationParams: {"count": _keycardCount.toString()})
                : FlutterI18n.translate(
                    context, _scooterAsleep ? "ls_settings_scooter_asleep" : "ls_settings_keycards_loading")),
            trailing: const Icon(Icons.chevron_right),
            onTap: _scooterAsleep
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsKeycardScreen())),
          ),
      ];

  List<Widget> _powerItems({required bool supportsScheduledHibernation}) => [
        ListTile(
          enabled: !_scooterAsleep,
          leading: const Icon(Icons.hourglass_bottom_rounded),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_auto_lock_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoLockDuration,
              hint: _timerDurationsLoaded || _scooterAsleep
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
              onChanged: !_timerDurationsLoaded || _isSendingAutoLock || _scooterAsleep
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
          enabled: !_scooterAsleep,
          leading: const Icon(Icons.bedtime_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_auto_hibernate_title")),
          subtitle: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_subtitle")),
          trailing: SizedBox(
            width: 128,
            child: DropdownButton<int>(
              isExpanded: true,
              menuWidth: 144,
              value: _autoHibernateDuration,
              hint: _timerDurationsLoaded || _scooterAsleep
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
              onChanged: !_timerDurationsLoaded || _isSendingAutoHibernate || _scooterAsleep
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
            enabled: !_scooterAsleep,
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
            onTap: _scooterAsleep
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LsScheduledHibernationScreen()),
                    ),
          ),
        if (!_scooterConnected || context.read<ScooterService>().identity.supportsBatteryKeepActive == true)
          ListTile(
            enabled: !_scooterAsleep,
            leading: Icon(Icons.battery_charging_full_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_battery_keep_active_title")),
            subtitle: _lsTitle(FlutterI18n.translate(context, "ls_settings_battery_keep_active_subtitle")),
            trailing: _batteryKeepActive == null
                ? (_scooterAsleep
                    ? _asleepValuePlaceholder()
                    : const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
                : Switch(
                    value: _batteryKeepActive!,
                    onChanged: _isSendingBatteryKeepActive || _scooterAsleep ? null : _setBatteryKeepActive,
                  ),
          ),
      ];

  List<Widget> _connectivityItems({
    required bool isLibrescoot,
    required bool supportsApnConfig,
  }) =>
      [
        ..._scooterAutoConnectItems(),
        if (isLibrescoot && (!_scooterConnected || supportsApnConfig))
          ListTile(
            enabled: !_scooterAsleep,
            leading: const Icon(Icons.cell_tower_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_apn_title")),
            subtitle: Text(_apnSubtitle(context)),
            trailing: _isSendingApn && !_scooterAsleep
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isSendingApn || _scooterAsleep ? null : _editApn,
          ),
      ];

  List<Widget> _updatesItems({
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        if (!connected || otaAvailable)
          ListTile(
            enabled: !_scooterAsleep,
            leading: const Icon(Icons.system_update_alt_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: _scooterAsleep
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsOtaScreen())),
          ),
        ListTile(
          enabled: !_scooterAsleep,
          leading: const Icon(Icons.usb_outlined),
          title: _lsTitle(FlutterI18n.translate(context, "ls_settings_update_mode_title")),
          subtitle: Text(usbMode == UsbMode.massStorage
              ? FlutterI18n.translate(context, "ls_settings_update_mode_on_subtitle")
              : FlutterI18n.translate(context, "ls_settings_update_mode_off_subtitle")),
          trailing: Switch(
            value: usbMode == UsbMode.massStorage,
            onChanged: _isUpdatingUsbMode || _scooterAsleep
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
      ];

  // Subsection heading plus items, omitted when empty.
  List<Widget> _section(String titleKey, List<Widget> items) => items.isEmpty
      ? const []
      : [Header(FlutterI18n.translate(context, titleKey), level: 1), ...items];

  List<Widget> _scooterSections({
    required bool isLibrescoot,
    required bool supportsScheduledHibernation,
    required bool supportsApnConfig,
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) {
    final sections = <Widget>[
      ..._section('settings_section_access_parking',
          _asleepAwareItems(_accessItems(isLibrescoot: isLibrescoot))),
      if (isLibrescoot)
        ..._section(
            'settings_section_power',
            _asleepAwareItems(
                _powerItems(supportsScheduledHibernation: supportsScheduledHibernation))),
      if (isLibrescoot)
        ..._section('ls_settings_section_alarm', _asleepAwareItems(alarmItems())),
      ..._section(
          'settings_section_connectivity',
          _asleepAwareItems(_connectivityItems(
            isLibrescoot: isLibrescoot,
            supportsApnConfig: supportsApnConfig,
          ))),
      if (isLibrescoot)
        ..._section(
            'settings_section_updates_service',
            _asleepAwareItems(_updatesItems(
              usbMode: usbMode,
              connected: connected,
              otaAvailable: otaAvailable,
            ))),
    ];
    // No scooter means no groups; asleep still gets the notice.
    if (sections.isEmpty && !_scooterAsleep) return const [];
    return [
      Header(
        FlutterI18n.translate(context, "stats_settings_section_scooter"),
        subtitle: _scooterAsleep
            ? '${_scooterScopeOnly()}. ${FlutterI18n.translate(context, "ls_settings_scooter_asleep")}'
            : _scooterScopeOnly(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      ...sections,
    ];
  }

  List<Widget> settingsItems({
    required bool isLibrescoot,
    required bool supportsScheduledHibernation,
    required bool supportsApnConfig,
    required UsbMode? usbMode,
    required bool connected,
    required bool otaAvailable,
  }) =>
      [
        ..._scooterSections(
          isLibrescoot: isLibrescoot,
          supportsScheduledHibernation: supportsScheduledHibernation,
          supportsApnConfig: supportsApnConfig,
          usbMode: usbMode,
          connected: connected,
          otaAvailable: otaAvailable,
        ),
        Header(FlutterI18n.translate(context, "stats_settings_section_app")),
        ..._section('settings_section_automation', _automationItems()),
        ..._section('settings_section_connection', _backgroundConnectionItems()),
        ..._section('settings_section_privacy_security', [
          ..._biometricsItems(),
          ..._locationConsentItems(),
          ..._activityLogItems(),
        ]),
        ..._section('settings_section_appearance', [
          ..._themeItems(),
          ..._languageItems(),
          ..._seasonalItems(),
        ]),
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
