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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_settings_title")),
      ),
      body: ListView(
        children: [
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
                          if (!context.mounted) return;
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
                        if (!context.mounted) return;
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
                        if (context.mounted) {
                          setState(() {
                            _isUpdatingUsbMode = false;
                          });
                        }
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
        ],
      ),
    );
  }
}
