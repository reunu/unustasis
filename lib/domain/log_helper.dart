// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_keyless_distance.dart';
import '../scooter_service.dart';

class LogHelper {
  // Private constructor
  LogHelper._internal();

  // Singleton instance
  static final LogHelper _instance = LogHelper._internal();

  // Factory constructor to return the same instance
  factory LogHelper() {
    return _instance;
  }

  final int maxBufferSize = 500; // Set a maximum number of log entries
  final List<Map<String, String>> _logBuffer = [];
  Timer? _cleanupTimer;

  void initialize() {
    Logger.root.onRecord.listen((record) {
      addLog(record);
    });
    _startLogCleanup();
  }

  void addLog(LogRecord record) {
    if (kDebugMode && record.level >= Level.INFO) {
      Fluttertoast.showToast(
        msg: record.message,
        fontSize: 12.0,
        backgroundColor:
            Colors.black.withValues(alpha: 0.7), // fluttertoast android logspams if no background color is set
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
    }
    // ignore: avoid_print
    print(record);
    // Ensure the buffer doesn't exceed the max size
    if (_logBuffer.length >= maxBufferSize) {
      _logBuffer.removeAt(0); // Remove the oldest log entry
    }
    _logBuffer.add({
      'time': record.time.toIso8601String(),
      'level': record.level.name,
      'message': record.message,
      'error': record.error?.toString() ?? '',
      'stackTrace': record.stackTrace?.toString() ?? ''
    });
  }

  void _startLogCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
      _logBuffer.removeWhere((log) => DateTime.parse(log['time']!).isBefore(cutoff));
    });
  }

  Future<File> saveLogsToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/logs.txt');
    final logString = _logBuffer.map((log) => jsonEncode(log)).join('\n');
    return file.writeAsString(logString);
  }

  static void startBugReport(BuildContext context) async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(FlutterI18n.translate(context, "settings_report")),
              content: Text(FlutterI18n.translate(context, "settings_report_description")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(FlutterI18n.translate(context, "settings_report_cancel"))),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(FlutterI18n.translate(context, "settings_report_proceed"))),
              ],
            )).then((confirmed) async {
      if (confirmed == true) {
        // write log file
        File logFile = await LogHelper().saveLogsToFile();

        // get some more device info to add to the body
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        String device, os;
        if (Platform.isIOS) {
          IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
          device = iosInfo.utsname.machine;
          os = iosInfo.systemVersion;
        } else if (Platform.isAndroid) {
          AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
          device = "${androidInfo.brand} ${androidInfo.model}";
          os = androidInfo.version.release;
        } else {
          device = "unknown";
          os = "unsupported";
        }

        SharedPreferencesAsync prefs = SharedPreferencesAsync();
        if (context.mounted) {
          ScooterService service = context.read<ScooterService>();
          final Email email = Email(
            body: '''${FlutterI18n.translate(context, "report_placeholder")}

-------------------------------
Device: $device
OS: $os
Settings: 
      backgroundScan = ${await prefs.getBool("backgroundScan") ?? false}
      biometrics = ${await prefs.getBool("biometrics") ?? false}
      autoUnlock = ${service.autoUnlock}
      autoUnlockDistance = ${ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold) ?? ScooterKeylessDistance.regular.threshold}
      openSeatOnUnlock = ${service.openSeatOnUnlock}
      hazardLocking = ${service.hazardLocking}
      osmConsent = ${await prefs.getBool("osmConsent") ?? true}
      seasonal = ${await prefs.getBool("seasonal") ?? true}
Saved scooters: ${await prefs.getString("savedScooters") ?? 'none'}
''',
            subject: FlutterI18n.translate(context, "report_subject"),
            recipients: ['unu@freal.de'],
            attachmentPaths: [logFile.path],
            isHTML: false,
          );

          await FlutterEmailSender.send(email);
        }
      }
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
  }
}
