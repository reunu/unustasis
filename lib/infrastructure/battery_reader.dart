import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/utils.dart';

class BatteryReader {
  final ScooterBattery _battery;
  final BluetoothCharacteristic? _socCharacteristic;
  final BehaviorSubject<DateTime?> _lastPingController;
  late final SharedPreferences? _sharedPrefs;

  static const lastPingCacheKey = "lastPing";

  BatteryReader(
      this._battery, this._socCharacteristic, this._lastPingController);

  readAndSubscribeSOC(BehaviorSubject<int?> socController) async {
    subscribeCharacteristic(_socCharacteristic!, (value) {
      int? soc = convertUint32ToInt(value);
      log("$_battery SOC received: $soc");
      // sometimes the scooter sends null. Ignoring those values...
      if (soc != null) {
        socController.add(soc);
        _writeSocToCache(soc);
      }
    });

    int? cachedSoc = await _readSocFromCache();
    socController.add(cachedSoc);
  }

  readAndSubscribeCycles(BluetoothCharacteristic? cyclesCharacteristic,
      BehaviorSubject<int?> cyclesController) {
    subscribeCharacteristic(cyclesCharacteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_battery battery cycles received: $cycles");
      cyclesController.add(cycles);
    });
  }

  Future<int?> _readSocFromCache() async {
    DateTime? lastPing = await _readLastPing();
    if (lastPing == null) {
      return null;
    }

    _lastPingController.add(lastPing);
    int? soc = (await _getSharedPrefs()).getInt(_getSocCacheKey(_battery));
    return soc;
  }

  Future<void> _writeSocToCache(int soc) async {
    _lastPingController.add(DateTime.now());
    (await _getSharedPrefs())
        .setInt(lastPingCacheKey, DateTime.now().microsecondsSinceEpoch);
    (await _getSharedPrefs()).setInt(_getSocCacheKey(_battery), soc);
  }

  String _getSocCacheKey(ScooterBattery battery) => "${battery.name}SOC";

  Future<DateTime?> _readLastPing() async {
    int? epoch = (await _getSharedPrefs()).getInt(lastPingCacheKey);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(epoch);
  }

  Future<SharedPreferences> _getSharedPrefs() async {
    return _sharedPrefs ??= await SharedPreferences.getInstance();
  }
}
