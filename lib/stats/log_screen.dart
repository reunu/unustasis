import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/statistics_helper.dart';

import '../scooter_service.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  String getScooterName(BuildContext context, bool multipleScootersInLog, String scooterId) {
    Map<String, SavedScooter> scooters = context.read<ScooterService>().savedScooters;
    if (!multipleScootersInLog) {
      return "";
    }
    if (!scooters.containsKey(scooterId)) {
      return "Scooter $scooterId: ";
    }
    return "${scooters[scooterId]?.name ?? "Scooter $scooterId"}: ";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "activity_log_title")),
      ),
      body: Column(
        children: [
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text(FlutterI18n.translate(context, "activity_log_disclaimer")),
            trailing: TextButton(
              child: Text(FlutterI18n.translate(context, "activity_log_clear"),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () async {
                bool confirm = await _confirmClearLogs(context);
                if (confirm && context.mounted) {
                  StatisticsHelper().clearEventLogs();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(FlutterI18n.translate(context, "activity_log_cleared"))),
                  );
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
          Divider(),
          Expanded(
            child: FutureBuilder(
                future: StatisticsHelper().getEventLogs(),
                builder: (context, snapshot) {
                  bool multipleScootersInLog =
                      snapshot.hasData && (snapshot.data as List<LogEntry>).map((e) => e.scooterId).toSet().length > 1;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text(FlutterI18n.translate(context, "activity_log_error")));
                  } else {
                    List<LogEntry> logs = snapshot.data as List<LogEntry>;
                    if (logs.isEmpty) {
                      return Center(child: Text(FlutterI18n.translate(context, "activity_log_empty")));
                    }
                    return ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        LogEntry log = logs[index];
                        return ListTile(
                          title: Text(
                              '${getScooterName(context, multipleScootersInLog, log.scooterId)}${log.source == EventSource.auto ? "auto " : ""}${log.eventType.toString().split('.').last}'),
                          subtitle:
                              Text('${log.timestamp.toIso8601String()}, from ${log.source.toString().split('.').last}'),
                          trailing: log.location != null
                              ? IconButton(
                                  icon: const Icon(Icons.map_outlined),
                                  onPressed: () {
                                    MapsLauncher.launchCoordinates(
                                      log.location!.latitude,
                                      log.location!.longitude,
                                    );
                                  },
                                )
                              : null,
                        );
                      },
                    );
                  }
                }),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClearLogs(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_title")),
            content: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_message")),
            actions: [
              TextButton(
                child: Text(FlutterI18n.translate(context, "cancel")),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text(FlutterI18n.translate(context, "activity_log_clear_confirm_button")),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }
}
