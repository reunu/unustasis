import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'ls_keycard_screen.dart';
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

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so that we have a valid context with
    // the ScooterService available via Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _getKeycardCount());
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
                value: 60,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_1_min")),
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
                value: 1,
                child: Text(FlutterI18n.translate(context, "ls_settings_duration_immediately")),
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
