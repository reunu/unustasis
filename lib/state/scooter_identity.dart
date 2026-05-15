import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

class ScooterIdentity {
  final _log = Logger('ScooterIdentity');

  String? name;
  int? color;
  DateTime? lastPing;
  LatLng? lastLocation;
  String? nrfVersion;
  bool? isLibrescoot;
  int? rssi;

  void wireNrfVersion(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
  }) {
    if (chars.nrfVersionCharacteristic != null) {
      _log.info('Reading nRF version');
      readNrfVersion(chars.nrfVersionCharacteristic!, (version, isLibre) {
        nrfVersion = version;
        isLibrescoot = isLibre;
        onUpdate();
      });
    }
  }
}
