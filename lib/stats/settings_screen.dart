import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/theme_helper.dart';
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
  bool _lsDataLoadStarted = false;
  bool _isSendingAutoLock = false;
  int? _autoLockDuration;
  bool _timerDurationsLoaded = false;
  bool _isSendingAutoHibernate = false;
  int? _autoHibernateDuration;
  int? _keycardCount;
  bool _isSendingApn = false;
  bool _isUpdatingUsbMode = false;
  bool _apnLoaded = false;
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
  void dispose() {
    _apnController.dispose();
    super.dispose();
  }

  void _ensureLsDataLoaded(bool isLibrescoot) {
    final service = context.read<ScooterService>();
    if (!isLibrescoot || !service.connected || _lsDataLoadStarted) return;
    _lsDataLoadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getKeycardCount();
      _getTimerDurations();
      _getApn();
    });
  }

  Future<void> _getKeycardCount() async {
    final count = await countKeycardsCommand(
      context.read<ScooterService>().myScooter,
      context.read<ScooterService>().characteristicRepository,
    );
    if (mounted) setState(() => _keycardCount = count);
  }

  Future<void> _getTimerDurations() async {
    try {
      final service = context.read<ScooterService>();
      final values = await Future.wait([
        getLsSettingCommand(service.myScooter, service.characteristicRepository, lsKeyAutoStandbySeconds),
        getLsSettingCommand(service.myScooter, service.characteristicRepository, lsKeyHibernateTimer),
      ]);
      if (!mounted) return;
      setState(() {
        _autoLockDuration = int.tryParse(values[0] ?? "");
        _autoHibernateDuration = int.tryParse(values[1] ?? "");
        _timerDurationsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _timerDurationsLoaded = true);
    }
  }

  Widget _timerLoadingIndicator() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Future<void> _getApn() async {
    String? apn;
    try {
      apn = await context.read<ScooterService>().getCellularApn();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _apn = apn;
        _apnLoaded = true;
      });
    }
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
    if (picked == null || !mounted) return;

    setState(() => _isSendingApn = true);
    try {
      final service = context.read<ScooterService>();
      if (picked.clear) {
        await service.clearCellularApn();
      } else {
        await service.setCellularApn(picked.value);
      }
      if (!mounted) return;
      setState(() => _apn = picked.value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          picked.clear ? "ls_settings_apn_cleared" : "ls_settings_apn_success",
        ))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(
          context,
          "ls_settings_apn_error",
          translationParams: {"error": e.toString()},
        ))),
      );
    } finally {
      if (mounted) setState(() => _isSendingApn = false);
    }
  }

  List<Widget> _librescootScooterSettingsItems({required bool supportsScheduledHibernation}) => [
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
                      if (value == null) return;
                      setState(() => _isSendingAutoLock = true);
                      try {
                        await setAutoStandbyTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        if (!mounted) return;
                        setState(() => _autoLockDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_success"))),
                        );
                      } catch (e) {
                        if (mounted) {
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
                        if (mounted) setState(() => _isSendingAutoLock = false);
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
                      if (value == null) return;
                      setState(() => _isSendingAutoHibernate = true);
                      try {
                        await setAutoHibernateTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        if (!mounted) return;
                        setState(() => _autoHibernateDuration = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(FlutterI18n.translate(context, "ls_settings_auto_hibernate_success"))),
                        );
                      } catch (e) {
                        if (mounted) {
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
                        if (mounted) setState(() => _isSendingAutoHibernate = false);
                      }
                    },
            ),
          ),
        ),
        if (supportsScheduledHibernation)
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
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
                    setState(() => _isUpdatingUsbMode = true);
                    try {
                      final service = context.read<ScooterService>();
                      if (value) {
                        await enterUMSModeCommand(service.myScooter, service.characteristicRepository);
                      } else {
                        await enterNormalUsbModeCommand(service.myScooter, service.characteristicRepository);
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(FlutterI18n.translate(
                          context,
                          value ? "ls_settings_update_mode_enter_success" : "ls_settings_update_mode_exit_success",
                        ))),
                      );
                    } catch (e) {
                      if (mounted) {
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
                      if (mounted) setState(() => _isUpdatingUsbMode = false);
                    }
                  },
          ),
        ),
        if (connected && otaAvailable)
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: _lsTitle(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsOtaScreen())),
          ),
        if (supportsApnConfig)
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        ),
        if (isLibrescoot)
          ..._librescootScooterSettingsItems(supportsScheduledHibernation: supportsScheduledHibernation),
        SwitchListTile(
          secondary: const Icon(Icons.key_outlined),
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
          secondary: const Icon(Icons.work_outline),
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
          secondary: const Icon(Icons.code_rounded),
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
        if (isLibrescoot) ...[
          Header(FlutterI18n.translate(context, "ls_settings_section_maintenance")),
          ..._librescootMaintenanceSettingsItems(
            supportsApnConfig: supportsApnConfig,
            usbMode: usbMode,
            connected: connected,
            otaAvailable: otaAvailable,
          ),
        ],
        Header(FlutterI18n.translate(context, "stats_settings_section_app")),
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
                secondary: const Icon(Icons.lock_outlined),
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
              setState(() {
                seasonal = value;
              });
            },
          ),
        Container(), // to force another divider at the end
      ];

  @override
  Widget build(BuildContext context) {
    final ls = context.select<
        ScooterService,
        ({
          bool isLibrescoot,
          bool supportsScheduled,
          bool supportsApn,
          UsbMode? usbMode,
          bool connected,
          bool otaAvailable
        })>(
      (service) => (
        isLibrescoot: service.identity.isLibrescoot == true,
        supportsScheduled: service.identity.supportsScheduledHibernation == true,
        supportsApn: service.identity.supportsApnConfig == true,
        usbMode: service.vehicle.usbMode,
        connected: service.connected,
        otaAvailable: service.connected && service.characteristicRepository.otaAvailable,
      ),
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
