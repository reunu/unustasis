import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Android's Doze and App Standby exemption.
///
/// Without it, an action arriving from another app can't start the background
/// service when it isn't already running: Android refuses the foreground
/// start. A widget tap is allowed because the launcher grants that privilege
/// along with the tap; a broadcast carries none.
class BatteryOptimization {
  static const MethodChannel _channel = MethodChannel(
    'de.freal.unustasis/battery_optimization',
  );

  static final Logger _log = Logger('BatteryOptimization');

  /// Only Android has the concept; everywhere else this is silently exempt.
  static bool get isSupported => Platform.isAndroid;

  /// Whether the app is currently exempt.
  static Future<bool> isIgnored() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException catch (e) {
      _log.warning('Could not read the battery optimization state', e);
      return false;
    } on MissingPluginException catch (e) {
      // Reached from a background isolate, where the channel isn't wired up.
      _log.warning('Battery optimization channel unavailable here', e);
      return false;
    }
  }

  /// Opens this app's settings page, where Battery sits one tap in. Android
  /// gives an app no way to drop its own exemption, so revoking goes through
  /// Settings even though granting doesn't.
  static Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
    } on PlatformException catch (e) {
      _log.warning('Could not open the battery optimization settings', e);
    }
  }

  /// Shows the system's own dialog. Returns whether it could be shown, not
  /// what the user chose: the dialog is a separate activity and this returns
  /// as soon as it's launched, so read [isIgnored] again once the app resumes.
  static Future<bool> request() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } on PlatformException catch (e) {
      _log.warning('Could not show the battery optimization dialog', e);
      return false;
    }
  }
}
