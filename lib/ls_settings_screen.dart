import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'ls_keycard_screen.dart';
import 'ls_ota_screen.dart';
import 'ls_scheduled_hibernation_screen.dart';
import 'scooter_service.dart';
import 'service/ble_commands.dart';
import 'state/vehicle_status.dart';

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
  bool _isSendingApn = false;
  bool _apnLoaded = false;
  String? _apn;
  bool _isSendingBatteryKeepActive = false;
  bool? _batteryKeepActive;

  // Owned here rather than per-dialog. showDialog's future completes on pop,
  // while the route is still animating out with the TextField attached, so a
  // controller disposed right after the await is torn down under a live field.
  final TextEditingController _apnController = TextEditingController();

  @override
  void dispose() {
    _apnController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so that we have a valid context with
    // the ScooterService available via Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getKeycardCount();
      _getApn();
      _getBatteryKeepActive();
    });
  }

  void _getKeycardCount() async {
    if (!mounted) return;
    int? count = await countKeycardsCommand(
      context.read<ScooterService>().myScooter,
      context.read<ScooterService>().characteristicRepository,
    );
    setState(() {
      _keycardCount = count;
    });
  }

  Future<void> _getApn() async {
    if (!mounted) return;
    String? apn;
    try {
      apn = await context.read<ScooterService>().getCellularApn();
    } catch (e) {
      apn = null;
    }
    if (!mounted) return;
    setState(() {
      _apn = apn;
      _apnLoaded = true;
    });
  }

  Future<void> _getBatteryKeepActive() async {
    if (!mounted) return;
    bool? enabled;
    try {
      enabled = await context.read<ScooterService>().getBatteryKeepActive();
    } catch (e) {
      enabled = null;
    }
    if (!mounted) return;
    setState(() {
      _batteryKeepActive = enabled;
    });
  }

  Future<void> _setBatteryKeepActive(bool enabled) async {
    setState(() {
      _isSendingBatteryKeepActive = true;
    });
    try {
      await context.read<ScooterService>().setBatteryKeepActive(enabled);
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (mounted) {
        setState(() {
          _isSendingBatteryKeepActive = false;
        });
      }
    }
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
          )),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_settings_apn_error",
              translationParams: {"error": e.toString()})),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingApn = false);
    }
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
                      setState(() => _isSendingTime = true);
                      try {
                        String? result = await sendLsExtendedCommand(
                            context.read<ScooterService>().myScooter,
                            context.read<ScooterService>().characteristicRepository,
                            "time:set ${DateTime.now().millisecondsSinceEpoch ~/ 1000}"); // time:set expects seconds
                        if (!mounted) return;
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
                        if (context.mounted) {
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
                    if (value != null) {
                      try {
                        setState(() {
                          _isSendingAutoLock = true;
                        });
                        await setAutoStandbyTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        setState(() {
                          _isSendingAutoLock = false;
                          _autoLockDuration = value;
                        });
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(FlutterI18n.translate(context, "ls_settings_auto_lock_success")),
                          ),
                        );
                      } catch (e) {
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
                    if (value != null) {
                      try {
                        setState(() {
                          _isSendingAutoHibernate = true;
                        });
                        await setAutoHibernateTimeCommand(
                          context.read<ScooterService>().myScooter,
                          context.read<ScooterService>().characteristicRepository,
                          Duration(seconds: value),
                        );
                        setState(() {
                          _isSendingAutoHibernate = false;
                          _autoHibernateDuration = value;
                        });
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              FlutterI18n.translate(context, "ls_settings_auto_hibernate_success"),
                            ),
                          ),
                        );
                      } catch (e) {
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
        if (context.watch<ScooterService>().identity.supportsScheduledHibernation == true)
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
        if (context.watch<ScooterService>().identity.supportsApnConfig == true)
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
                    setState(() {
                      _isUpdatingUsbMode = true;
                    });

                    try {
                      if (value == true) {
                        await enterUMSModeCommand(context.read<ScooterService>().myScooter,
                            context.read<ScooterService>().characteristicRepository);
                      } else {
                        await enterNormalUsbModeCommand(context.read<ScooterService>().myScooter,
                            context.read<ScooterService>().characteristicRepository);
                      }
                      if (!mounted) return;
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(FlutterI18n.translate(context, "ls_settings_update_mode_error",
                              translationParams: {"error": e.toString()})),
                        ),
                      );
                    } finally {
                      setState(() {
                        _isUpdatingUsbMode = false;
                      });
                    }
                  },
          ),
        ),
        if (context.watch<ScooterService>().identity.supportsBatteryKeepActive == true)
          ListTile(
            leading: Icon(Icons.battery_charging_full_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_battery_keep_active_subtitle")),
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
        ListTile(
          leading: Icon(Icons.vpn_key_outlined),
          title: Text(FlutterI18n.translate(context, "ls_keycard_title")),
          subtitle: Text(_keycardCount != null
              ? FlutterI18n.translate(context, "ls_settings_keycards_count",
                  translationParams: {"count": _keycardCount.toString()})
              : FlutterI18n.translate(context, "ls_settings_keycards_loading")),
          trailing: Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => LsKeycardScreen()));
          },
        ),
        if (context.read<ScooterService>().connected &&
            context.read<ScooterService>().characteristicRepository.otaAvailable)
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
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_settings_title")),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shrinkWrap: true,
          itemCount: settingsItems().length,
          separatorBuilder: (context, index) => Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          itemBuilder: (context, index) => settingsItems()[index],
        ),
      ),
    );
  }
}
