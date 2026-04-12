import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/service/ble_commands.dart';

class LsSettingsScreen extends StatefulWidget {
  const LsSettingsScreen({super.key});

  @override
  State<LsSettingsScreen> createState() => _LsSettingsScreenState();
}

class _LsSettingsScreenState extends State<LsSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: Icon(Icons.update),
            label: Text("Update mode"),
            onPressed: () async {
              String? result = await sendLsExtendedCommand(context.read<ScooterService>().myScooter,
                  context.read<ScooterService>().characteristicRepository, "usb:ums");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Command result: $result"),
                ),
              );
            },
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.update_disabled),
            label: Text("Regular mode"),
            onPressed: () async {
              String? result = await sendLsExtendedCommand(context.read<ScooterService>().myScooter,
                  context.read<ScooterService>().characteristicRepository, "usb:normal");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Command result: $result"),
                ),
              );
            },
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.key_outlined),
            label: Text("List keycards"),
            onPressed: () async {
              List<String> keycards = await listKeycardsCommand(
                  context.read<ScooterService>().myScooter, context.read<ScooterService>().characteristicRepository);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Keycards: ${keycards.join(", ")}"),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
