import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/infrastructure/utils.dart';

class StateOfChargeReader {
  final String _name;
  final BluetoothCharacteristic? _characteristic;
  final BehaviorSubject<DateTime?> _lastPingController;
  late SharedPreferences _sharedPrefs;

  StateOfChargeReader(this._name, this._characteristic, this._lastPingController);

  readAndSubscribe(Function(int?) callback) {
    subscribeCharacteristic(_characteristic!, (value) {
      int? soc = convertUint32ToInt(value);
      log("$_name SOC received: $soc");
      callback(soc);
      _cache(soc);
    });
  }

  void _cache(int? soc) {
    if (soc != null) {
      _ping();
      _getSharedPrefs().setInt("${_name}SOC", soc);
    }
  }

  void _ping() async {
    _lastPingController.add(DateTime.now());
    _getSharedPrefs().setInt("lastPing", DateTime.now().microsecondsSinceEpoch);
  }

  _getSharedPrefs() async {
    _sharedPrefs = await SharedPreferences.getInstance();
    return _sharedPrefs;
  }
}
