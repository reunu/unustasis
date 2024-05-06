import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_battery.dart';

enum CacheKey {
  lastPing;
}

class CacheManager {
  static SharedPreferences? _sharedPrefs;

  static writeSOC(ScooterBattery battery, int soc) async {
    return (await _getSharedPrefs()).setInt(getSocCacheKey(battery), soc);
  }

  static Future<int?> readSOC(ScooterBattery battery) async {
    return (await _getSharedPrefs()).getInt(getSocCacheKey(battery));
  }

  static String getSocCacheKey(ScooterBattery battery) => "${battery.name}SOC";

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
