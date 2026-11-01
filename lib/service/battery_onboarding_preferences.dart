import 'package:shared_preferences/shared_preferences.dart';

const batteryFeatureOnboardingVersionKey = 'batteryFeatureOnboardingVersion';
const currentBatteryFeatureOnboardingVersion = 1;

class BatteryOnboardingPreferences {
  BatteryOnboardingPreferences({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;

  Future<bool> hasSeenBatteryFeature() async =>
      (await _preferences.getInt(batteryFeatureOnboardingVersionKey) ?? 0) >= currentBatteryFeatureOnboardingVersion;

  Future<void> markBatteryFeatureSeen() =>
      _preferences.setInt(batteryFeatureOnboardingVersionKey, currentBatteryFeatureOnboardingVersion);
}
