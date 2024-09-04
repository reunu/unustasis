import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

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
    });
    _startLogCleanup();
  }

  void _startLogCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
      _logBuffer
          .removeWhere((log) => DateTime.parse(log['time']!).isBefore(cutoff));
    });
  }

  Future<File> saveLogsToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/logs.txt');
    final logString = _logBuffer.map((log) => jsonEncode(log)).join('\n');
    return file.writeAsString(logString);
  }

  void dispose() {
    _cleanupTimer?.cancel();
  }
}
