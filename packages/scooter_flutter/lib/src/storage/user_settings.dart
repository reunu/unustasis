import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('UserSettings');

class UserSettings {
  final SharedPreferencesAsync _prefs;
  final void Function(Map<String, dynamic>)? _onUpdate;

  bool autoUnlock = false;
  int autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool optionalAuth = false;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;
  bool warnOfUnlockedHandlebars = true;

  UserSettings({
    SharedPreferencesAsync? preferences,
    void Function(Map<String, dynamic>)? onUpdate,
  })  : _prefs = preferences ?? SharedPreferencesAsync(),
        _onUpdate = onUpdate;

  Future<void> restore() async {
    autoUnlock = await _prefs.getBool("autoUnlock") ?? false;
    autoUnlockThreshold = await _prefs.getInt("autoUnlockThreshold") ??
        ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(await _prefs.getBool("biometrics") ?? false);
    openSeatOnUnlock = await _prefs.getBool("openSeatOnUnlock") ?? false;
    hazardLocking = await _prefs.getBool("hazardLocking") ?? false;
    warnOfUnlockedHandlebars =
        await _prefs.getBool("unlockedHandlebarsWarning") ?? true;
    _log.info("Restored cached settings");
  }

  Future<void> setAutoUnlock(bool enabled) async {
    autoUnlock = enabled;
    await _prefs.setBool("autoUnlock", enabled);
    _onUpdate?.call({"autoUnlock": enabled});
  }

  Future<void> setAutoUnlockThreshold(int threshold) async {
    autoUnlockThreshold = threshold;
    await _prefs.setInt("autoUnlockThreshold", threshold);
    _onUpdate?.call({"autoUnlockThreshold": threshold});
  }

  Future<void> setOpenSeatOnUnlock(bool enabled) async {
    openSeatOnUnlock = enabled;
    await _prefs.setBool("openSeatOnUnlock", enabled);
    _onUpdate?.call({"openSeatOnUnlock": enabled});
  }

  Future<void> setHazardLocking(bool enabled) async {
    hazardLocking = enabled;
    await _prefs.setBool("hazardLocking", enabled);
    _onUpdate?.call({"hazardLocking": enabled});
  }
}
