import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/infrastructure/shared_pref_key.dart';
import 'package:unustasis/infrastructure/utils.dart';

class StateOfChargeReader {
  final String _name;
  final BluetoothCharacteristic? _characteristic;
  final BehaviorSubject<int?> _socController;
  final BehaviorSubject<DateTime?> _lastPingController;
  late SharedPreferences _sharedPrefs;

  final String _lastPingCacheKey = SharedPrefKey.lastPing.name;
  late String _socCacheKey;

  StateOfChargeReader(this._name, this._characteristic, this._socController,
      this._lastPingController) {
    _socCacheKey = "${_name}SOC";
  }

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
    int? lastPing = _getSharedPrefs().getInt(_lastPingCacheKey);
    if (lastPing == null) {
      return;
    }

    _lastPingController.add(DateTime.fromMicrosecondsSinceEpoch(lastPing));
    _socController.add(_getSharedPrefs().getInt(_socCacheKey));
  }

  void _writeCache(int? soc) {
    if (soc == null) {
      return;
    }

    _ping();
    _getSharedPrefs().setInt(_socCacheKey, soc);
  }

  void _ping() async {
    _lastPingController.add(DateTime.now());
    _getSharedPrefs()
        .setInt(_lastPingCacheKey, DateTime.now().microsecondsSinceEpoch);
  }

  _getSharedPrefs() async {
    _sharedPrefs = await SharedPreferences.getInstance();
    return _sharedPrefs;
  }
}
