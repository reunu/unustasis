import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../scooter_service.dart';

class VersionReader {
  final log = Logger("VersionReader");
  final BluetoothCharacteristic _characteristic;
  final ScooterService _service;

  VersionReader(this._characteristic, this._service);

  Future<void> readOnce() async {
    try {
      // Read the characteristic value once
      List<int> value = await _characteristic.read();
      String version = _convertBytesToString(value);

      log.info("nRF version received: $version");

      // Store the full version string
      _service.nrfVersion = version;

      // Check if this is a librescoot version (contains "-ls" suffix)
      bool isLibrescoot = version.contains("-ls");
      _service.isLibrescoot = isLibrescoot;

      log.info("Librescoot detected: $isLibrescoot");
    } catch (e, stack) {
      log.warning("Failed to read nRF version characteristic", e, stack);
      // Set both to null on failure
      _service.nrfVersion = null;
      _service.isLibrescoot = null;
    }
  }

  String _convertBytesToString(List<int> value) {
    var withoutZeros = value.where((element) => element != 0).toList();
    return ascii.decode(withoutZeros).trim();
  }
}
