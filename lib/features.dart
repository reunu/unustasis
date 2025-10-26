import 'package:shared_preferences/shared_preferences.dart';

class Features {
  static const String _cloudConnectivityKey = 'feature_cloud_connectivity';
  
  // Feature flags
  static Future<bool> get isCloudConnectivityEnabled async {
    final prefs = await SharedPreferences.getInstance();
    // Cloud connectivity is disabled by default, can be enabled via developer options
    return prefs.getBool(_cloudConnectivityKey) ?? false;
  }
  
  static Future<void> setCloudConnectivityEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudConnectivityKey, enabled);
  }
  
  // Developer feature toggle (for testing/development)
  static Future<void> toggleCloudConnectivity() async {
    final current = await isCloudConnectivityEnabled;
    await setCloudConnectivityEnabled(!current);
  }
}