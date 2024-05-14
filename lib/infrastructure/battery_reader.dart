import 'dart:async';
import 'dart:developer';

import 'package:clock/clock.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/string_reader.dart';
import 'package:unustasis/infrastructure/utils.dart';

class BatteryReader {
  final ScooterBattery _battery;
  final BehaviorSubject<DateTime?> _lastPingController;

  static const lastPingCacheKey = "lastPing";

  BatteryReader(this._battery, this._lastPingController);

  readAndSubscribeSOC(BluetoothCharacteristic socCharacteristic,
      BehaviorSubject<int?> socController) async {
    var c = Completer();
    subscribeCharacteristic(socCharacteristic, (value) async {
      int? soc = convertUint32ToInt(value);
      log("$_battery SOC received: $soc");
      // sometimes the scooter sends null. Ignoring those values...
      if (soc != null) {
        socController.add(soc);
        await _writeSocToCache(soc);
      }
      c.complete();
    });

    // wait for written values
    await c.future;

    int? cachedSoc = await _readSocFromCache();
    socController.add(cachedSoc);
  }

  readAndSubscribeCycles(BluetoothCharacteristic cyclesCharacteristic,
      BehaviorSubject<int?> cyclesController) async {
    subscribeCharacteristic(cyclesCharacteristic, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_battery battery cycles received: $cycles");
      cyclesController.add(cycles);
    });
  }

  readAndSubscribeCharging(BluetoothCharacteristic chargingCharacteristic,
      BehaviorSubject<bool?> chargingController) {
    StringReader("${_battery.name} charging", chargingCharacteristic)
        .readAndSubscribe((String chargingState) {
      if (chargingState == "charging") {
        chargingController.add(true);
      } else if (chargingState == "not-charging") {
        chargingController.add(false);
      }
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
    _lastPingController.add(clock.now());
    var sharedPrefs = await _getSharedPrefs();
    await sharedPrefs.setInt(_getSocCacheKey(_battery), soc);
    await sharedPrefs.setInt(
        lastPingCacheKey, clock.now().microsecondsSinceEpoch);
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
    return await SharedPreferences.getInstance();
  }
}
