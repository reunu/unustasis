import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/helper_widgets/header.dart';
import 'package:unustasis/ls_keycard_screen.dart';
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
      body: ListView(
        children: [
          Header(
            "Librescoot Settings",
            subtitle: "These options are only available on scooters running librescoot.",
          ),
          ListTile(
            leading: Icon(Icons.access_time_outlined),
            title: Text("Scooter clock"),
            subtitle: Text("Sets the scooter's internal clock to this phone's current time."),
            trailing: ElevatedButton(
                child: Text("Send"),
                onPressed: () async {
                  String? result = await sendLsExtendedCommand(
                      context.read<ScooterService>().myScooter,
                      context.read<ScooterService>().characteristicRepository,
                      "time:set ${DateTime.now().millisecondsSinceEpoch}");
                  if (!context.mounted) return;
                  if (result == "time:ok") {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Scooter time updated successfully!"),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Failed to update scooter time. Result: $result"),
                      ),
                    );
                  }
                }),
          ),
          ListTile(
            leading: Icon(Icons.usb_outlined),
            title: Text("Update mode"),
            subtitle: Text("Switches the scooter into update mode"),
            trailing: ElevatedButton(
                child: Text("Send"),
                onPressed: () async {
                  String? result = await sendLsExtendedCommand(context.read<ScooterService>().myScooter,
                      context.read<ScooterService>().characteristicRepository, "usb:ums");
                  if (!context.mounted) return;
                  if (result == "usb:ok") {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Scooter is now in update mode!"),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Failed to switch scooter to update mode. Result: $result"),
                      ),
                    );
                  }
                }),
          ),
          ListTile(
            leading: Icon(Icons.usb_off_outlined),
            title: Text("Regular mode"),
            subtitle: Text("Switches the scooter back into regular mode"),
            trailing: ElevatedButton(
                child: Text("Send"),
                onPressed: () async {
                  String? result = await sendLsExtendedCommand(context.read<ScooterService>().myScooter,
                      context.read<ScooterService>().characteristicRepository, "usb:mss");
                  if (!context.mounted) return;
                  if (result == "usb:ok") {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Scooter is now in regular mode!"),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Failed to switch scooter to regular mode. Result: $result"),
                      ),
                    );
                  }
                }),
          ),
          ListTile(
            leading: Icon(Icons.vpn_key_outlined),
            title: Text("Keycards"),
            subtitle: FutureBuilder<String?>(
                future: sendLsExtendedCommand(context.read<ScooterService>().myScooter,
                    context.read<ScooterService>().characteristicRepository, "keycard:count"),
                builder: (context, snapshot) =>
                    Text(snapshot.hasData ? "${snapshot.data} cards currently stored" : "Loading...")),
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
