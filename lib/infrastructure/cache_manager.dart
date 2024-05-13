import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_battery.dart';

enum CacheKey {
  lastPing;
}

class CacheManager {
  static final CacheManager _singleton = CacheManager._internal();
  static SharedPreferences? _sharedPrefs;

  factory CacheManager() {
    return _singleton;
  }

  CacheManager._internal();

  writeSOC(ScooterBattery battery, int soc) async {
    return (await _getSharedPrefs()).setInt(getSocCacheKey(battery), soc);
  }

  Future<int?> readSOC(ScooterBattery battery) async {
    return (await _getSharedPrefs()).getInt(getSocCacheKey(battery));
  }

  String getSocCacheKey(ScooterBattery battery) => "${battery.name}SOC";

  writeLastPing() async {
    (await _getSharedPrefs())
        .setInt(CacheKey.lastPing.name, DateTime.now().microsecondsSinceEpoch);
  }

  Future<DateTime?> readLastPing() async {
    int? epoch = (await _getSharedPrefs()).getInt(CacheKey.lastPing.name);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(epoch);
  }

  Future<SharedPreferences> _getSharedPrefs() async {
    return _sharedPrefs ??= await SharedPreferences.getInstance();
  }
}
