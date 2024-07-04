import 'dart:async';
import 'dart:developer';

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
      int? soc;
      if (_battery == ScooterBattery.cbb) {
        soc = value[0];
      } else {
        soc = _convertUint32ToInt(value);
      }
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
    if (cachedSoc != null) {
      socController.add(cachedSoc);
    }
  }

  readAndSubscribeCycles(BluetoothCharacteristic cyclesCharacteristic,
      BehaviorSubject<int?> cyclesController) async {
    subscribeCharacteristic(cyclesCharacteristic, (value) {
      int? cycles = _convertUint32ToInt(value);
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
    var sharedPrefs = await _getSharedPrefs();
    int? soc = sharedPrefs.getInt(_getSocCacheKey(_battery));
    return soc;
  }

  Future<void> _writeSocToCache(int soc) async {
    _lastPingController.add(DateTime.now());
    var sharedPrefs = await _getSharedPrefs();
    await sharedPrefs.setInt(_getSocCacheKey(_battery), soc);
    await sharedPrefs.setInt(
        lastPingCacheKey, DateTime.now().microsecondsSinceEpoch);
  }

  String _getSocCacheKey(ScooterBattery battery) => "${battery.name}SOC";

  Future<DateTime?> _readLastPing() async {
    var sharedPrefs = await _getSharedPrefs();
    int? epoch = sharedPrefs.getInt(lastPingCacheKey);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(epoch);
  }

  Future<SharedPreferences> _getSharedPrefs() async {
    return await SharedPreferences.getInstance();
  }

  int? _convertUint32ToInt(List<int> uint32data) {
    log("Converting $uint32data to int.");
    if (uint32data.length != 4) {
      log("Received empty data for uint32 conversion. Ignoring.");
      return null;
    }

    // Little-endian to big-endian interpretation (important for proper UInt32 conversion)
    return (uint32data[3] << 24) +
        (uint32data[2] << 16) +
        (uint32data[1] << 8) +
        uint32data[0];
  }
}
