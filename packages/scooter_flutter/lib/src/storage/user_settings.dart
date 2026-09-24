import 'package:logging/logging.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('UserSettings');

class UserSettings {
  final SharedPreferencesAsync _prefs;
  final void Function(Map<String, dynamic>)? _onUpdate;

  int autoUnlockThreshold = ScooterKeylessDistance.regular.threshold;
  bool optionalAuth = false;
  bool warnOfUnlockedHandlebars = true;

  /// Phone-wide keyless flags from before they became per-scooter. Read once so
  /// the per-scooter migration can seed existing scooters with what the user
  /// had chosen; nothing writes them any more.
  bool legacyAutoUnlock = false;
  bool legacyHazardLocking = false;
  bool legacyOpenSeatOnUnlock = false;

  UserSettings({
    SharedPreferencesAsync? preferences,
    void Function(Map<String, dynamic>)? onUpdate,
  })  : _prefs = preferences ?? SharedPreferencesAsync(),
        _onUpdate = onUpdate;

  Future<void> restore() async {
    autoUnlockThreshold = await _prefs.getInt("autoUnlockThreshold") ??
        ScooterKeylessDistance.regular.threshold;
    optionalAuth = !(await _prefs.getBool("biometrics") ?? false);
    legacyAutoUnlock = await _prefs.getBool("autoUnlock") ?? false;
    legacyOpenSeatOnUnlock = await _prefs.getBool("openSeatOnUnlock") ?? false;
    legacyHazardLocking = await _prefs.getBool("hazardLocking") ?? false;
    warnOfUnlockedHandlebars =
        await _prefs.getBool("unlockedHandlebarsWarning") ?? true;
    _log.info("Restored cached settings");
  }

  Future<void> setAutoUnlockThreshold(int threshold) async {
    autoUnlockThreshold = threshold;
    await _prefs.setInt("autoUnlockThreshold", threshold);
    _onUpdate?.call({"autoUnlockThreshold": threshold});
  }
}
