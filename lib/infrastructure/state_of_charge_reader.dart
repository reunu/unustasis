import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:unustasis/infrastructure/cache_manager.dart';
import 'package:unustasis/infrastructure/utils.dart';

class StateOfChargeReader {
  final String _name;
  final BluetoothCharacteristic? _characteristic;
  final BehaviorSubject<int?> _socController;
  final BehaviorSubject<DateTime?> _lastPingController;

  StateOfChargeReader(this._name, this._characteristic, this._socController,
      this._lastPingController);

  readAndSubscribe() {
    subscribeCharacteristic(_characteristic!, (value) {
      int? soc = convertUint32ToInt(value);
      log("$_name SOC received: $soc");
      _socController.add(soc);
      _writeCache(soc);
    });

    _readCache();
  }

  void _readCache() {
    DateTime? lastPing = CacheManager.readLastPing();
    if (lastPing == null) {
      return;
    }

    _lastPingController.add(lastPing);
    _socController.add(CacheManager.readSOC(_name));
  }

  void _writeCache(int? soc) {
    if (soc == null) {
      return;
    }

    _lastPingController.add(DateTime.now());
    CacheManager.writeLastPing();
    CacheManager.writeSOC(_name, soc);
  }
}
