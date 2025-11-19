import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../domain/scooter_type.dart';
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

      // Determine scooter type based on version suffix ("-ls" => librescoot)
      bool isLibrescoot = version.contains("-ls");
      final inferredType = isLibrescoot ? ScooterType.unuProLS : ScooterType.unuPro;

      // Only update & persist if changed to avoid unnecessary writes / background chatter
      if (_service.scooterType != inferredType) {
        _service.scooterType = inferredType; // setter handles persistence & propagation
        log.info("Scooter type inferred from version: ${inferredType.name}");
      } else {
        log.fine("Scooter type already set to ${inferredType.name}, skipping update");
      }

      log.info("Librescoot detected: $isLibrescoot");
    } catch (e, stack) {
      log.warning("Failed to read nRF version characteristic", e, stack);
      // Set to null on failure
      _service.nrfVersion = null;
    }
  }

  String _convertBytesToString(List<int> value) {
    var withoutZeros = value.where((element) => element != 0).toList();
    return ascii.decode(withoutZeros).trim();
  }
}
