import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/infrastructure/cache_manager.dart';

void main() {
  group('CacheManager', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('writes and reads SOC from shared preferences', () async {
      int soc = 1;
      await CacheManager.writeSOC("test", soc);
      expect(await CacheManager.readSOC("test"), equals(soc));
    });

    test('writes and reads last ping from shared preferences', () async {
      await CacheManager.writeLastPing();
      expect(await CacheManager.readLastPing(), isNot(equals(null)));
    });
  });
}
