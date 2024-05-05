import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/infrastructure/cache_key.dart';

class CacheManager {
  static writeSOC(name, soc) {
    return _getSharedPrefs().writeInt(getSocCacheKey(name), soc);
  }

  static readSOC(String name) {
    return _getSharedPrefs().getInt(getSocCacheKey(name));
  }

  static String getSocCacheKey(String name) => "${name}SOC";

  static writeLastPing() {
    _getSharedPrefs()
        .setInt(CacheKey.lastPing.name, DateTime.now().microsecondsSinceEpoch);
  }

  static DateTime? readLastPing() {
    int? epoch = _getSharedPrefs().getInt(CacheKey.lastPing.name);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(epoch);
  }

  static _getSharedPrefs() async {
    return await SharedPreferences.getInstance();
  }
}
