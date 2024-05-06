import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/cache_manager.dart';
import 'package:unustasis/infrastructure/utils.dart';

class StateOfChargeReader {
  final ScooterBattery _battery;
  final BluetoothCharacteristic? _characteristic;
  final BehaviorSubject<int?> _socController;
  final BehaviorSubject<DateTime?> _lastPingController;

  StateOfChargeReader(this._battery, this._characteristic, this._socController,
      this._lastPingController);

  readAndSubscribe() {
    subscribeCharacteristic(_characteristic!, (value) {
      int? soc = convertUint32ToInt(value);
      log("$_battery SOC received: $soc");
      // sometimes the scooter sends null. Ignoring those values...
      if (soc != null) {
        _socController.add(soc);
        _writeCache(soc);
      }
    });

    _readCache();
  }

  Future<void> _readCache() async {
    DateTime? lastPing = await CacheManager.readLastPing();
    if (lastPing == null) {
      return;
    }

    _lastPingController.add(lastPing);
    _socController.add(await CacheManager.readSOC(_battery));
  }

  void _writeCache(int soc) {
    _lastPingController.add(DateTime.now());
    CacheManager.writeLastPing();
    CacheManager.writeSOC(_battery, soc);
  }
}
