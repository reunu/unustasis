import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'ls_ota_screen.dart';
import 'scooter_service.dart';
import 'service/ble_commands.dart';
import 'state/vehicle_status.dart';

/// Immediate Librescoot actions and live status.
///
/// Persistent Librescoot configuration belongs in the app Settings screen.
class LsSettingsScreen extends StatefulWidget {
  const LsSettingsScreen({super.key});

  @override
  State<LsSettingsScreen> createState() => _LsSettingsScreenState();
}

class _LsSettingsScreenState extends State<LsSettingsScreen> {
  bool _isUpdatingUsbMode = false;
  bool _isSendingTime = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
    });
  }

  List<Widget> settingsItems() => [
        ListTile(
          leading: const Icon(Icons.access_time_outlined),
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
                      final result = await sendLsExtendedCommand(
                        context.read<ScooterService>().myScooter,
                        context.read<ScooterService>().characteristicRepository,
                        "time:set ${DateTime.now().millisecondsSinceEpoch ~/ 1000}",
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(FlutterI18n.translate(
                            context,
                            result == "time:ok" ? "ls_settings_clock_success" : "ls_settings_clock_error",
                            translationParams: result == "time:ok" ? null : {"result": result ?? ""},
                          )),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _isSendingTime = false);
                    }
                  },
            child: _isSendingTime
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(FlutterI18n.translate(context, "ls_settings_clock_send")),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.usb_outlined),
          title: Text(FlutterI18n.translate(context, "ls_settings_update_mode_title")),
          subtitle: Text(context.watch<ScooterService>().vehicle.usbMode == UsbMode.massStorage
              ? FlutterI18n.translate(context, "ls_settings_update_mode_on_subtitle")
              : FlutterI18n.translate(context, "ls_settings_update_mode_off_subtitle")),
          trailing: Switch(
            value: context.watch<ScooterService>().vehicle.usbMode == UsbMode.massStorage,
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
        if (context.read<ScooterService>().connected &&
            context.read<ScooterService>().characteristicRepository.otaAvailable)
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: Text(FlutterI18n.translate(context, "ls_settings_ota_title")),
            subtitle: Text(FlutterI18n.translate(context, "ls_settings_ota_subtitle")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LsOtaScreen())),
          ),
        Container(),
      ];

  @override
  Widget build(BuildContext context) {
    final items = settingsItems();
    return Scaffold(
      appBar: AppBar(title: const Text("Librescoot")),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
