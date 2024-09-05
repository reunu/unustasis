import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../infrastructure/utils.dart';

class StringReader {
  final log = Logger("StringReader");
  final String _name;
  final BluetoothCharacteristic _characteristic;

  StringReader(this._name, this._characteristic);

  readAndSubscribe(Function(String) callback) {
    subscribeCharacteristic(_characteristic, (value) {
      log.info("$_name received: ${ascii.decode(value)}");
      String state = _convertBytesToString(value);
      callback(state);
    });
  }

  String _convertBytesToString(List<int> value) {
    var withoutZeros = value.where((element) => element != 0).toList();
    return ascii.decode(withoutZeros).trim();
  }
}
