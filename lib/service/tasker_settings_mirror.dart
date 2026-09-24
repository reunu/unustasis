import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native Tasker configuration cannot read Flutter's DataStore preferences.
Future<void> mirrorTaskerBackgroundScan(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('taskerBackgroundScan', enabled)) {
      throw StateError('Tasker scan setting could not be stored');
    }
  } catch (error, stack) {
    Logger('TaskerSettingsMirror').warning('Could not update the Tasker scan setting', error, stack);
  }
}
