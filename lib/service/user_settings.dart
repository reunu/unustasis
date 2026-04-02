import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_keyless_distance.dart';

final _log = Logger('UserSettings');

class UserSettings {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final bool _isInBackgroundService;

  bool autoUnlock = false;
  int autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool optionalAuth = false;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;
  bool warnOfUnlockedHandlebars = true;

  UserSettings({bool isInBackgroundService = false})
      : _isInBackgroundService = isInBackgroundService;

  Future<void> restore() async {
    autoUnlock = await _prefs.getBool("autoUnlock") ?? false;
    autoUnlockThreshold =
        await _prefs.getInt("autoUnlockThreshold") ?? ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(await _prefs.getBool("biometrics") ?? false);
    openSeatOnUnlock = await _prefs.getBool("openSeatOnUnlock") ?? false;
    hazardLocking = await _prefs.getBool("hazardLocking") ?? false;
    warnOfUnlockedHandlebars = await _prefs.getBool("unlockedHandlebarsWarning") ?? true;
    _log.info("Restored cached settings");
  }

  void setAutoUnlock(bool enabled) {
    autoUnlock = enabled;
    _prefs.setBool("autoUnlock", enabled);
    _updateBackgroundService({"autoUnlock": enabled});
  }

  void setAutoUnlockThreshold(int threshold) {
    autoUnlockThreshold = threshold;
    _prefs.setInt("autoUnlockThreshold", threshold);
    _updateBackgroundService({"autoUnlockThreshold": threshold});
  }

  void setOpenSeatOnUnlock(bool enabled) {
    openSeatOnUnlock = enabled;
    _prefs.setBool("openSeatOnUnlock", enabled);
    _updateBackgroundService({"openSeatOnUnlock": enabled});
  }

  void setHazardLocking(bool enabled) {
    hazardLocking = enabled;
    _prefs.setBool("hazardLocking", enabled);
    _updateBackgroundService({"hazardLocking": enabled});
  }

  void _updateBackgroundService(Map<String, dynamic> data) {
    if (!_isInBackgroundService) {
      FlutterBackgroundService().invoke("update", data);
    }
  }
}
