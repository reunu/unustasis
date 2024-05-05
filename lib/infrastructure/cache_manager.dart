import 'package:shared_preferences/shared_preferences.dart';

enum CacheKey {
  lastPing;
}

class CacheManager {
  static SharedPreferences? _sharedPrefs;

  static writeSOC(String name, int soc) async {
    return (await _getSharedPrefs()).setInt(getSocCacheKey(name), soc);
  }

  static Future<int?> readSOC(String name) async {
    return (await _getSharedPrefs()).getInt(getSocCacheKey(name));
  }

  static String getSocCacheKey(String name) => "${name}SOC";

  static writeLastPing() async {
    (await _getSharedPrefs())
        .setInt(CacheKey.lastPing.name, DateTime.now().microsecondsSinceEpoch);
  }

  static Future<DateTime?> readLastPing() async {
    int? epoch = (await _getSharedPrefs()).getInt(CacheKey.lastPing.name);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(epoch);
  }

  static Future<SharedPreferences> _getSharedPrefs() async {
    return _sharedPrefs ??= await SharedPreferences.getInstance();
  }
}
