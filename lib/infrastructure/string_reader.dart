import 'dart:developer';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:unustasis/infrastructure/utils.dart';

class StringReader {
  final String _name;
  final BluetoothCharacteristic? _characteristic;

  StringReader(this._name, this._characteristic);

  readAndSubscribe(Function(String) callback) {
    subscribeCharacteristic(_characteristic!, (value) {
      log("$_name received: ${ascii.decode(value)}");
      String state = _convertBytesToString(value);
      callback(state);
    });
  }

  String _convertBytesToString(List<int> value) {
    value.removeWhere((element) => element == 0);
    String state = ascii.decode(value).trim();
    return state;
  }
}
