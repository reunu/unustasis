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
  int? odometerMeters;

  // librescoot capability flags, probed after each connection.
  // null = unknown / not yet probed.
  bool? supportsHibernateFor;
  bool? supportsScheduledHibernation;
  bool? supportsApnConfig;
  bool? supportsBondForget;

  void resetLsCapabilities() {
    supportsHibernateFor = null;
    supportsScheduledHibernation = null;
    supportsApnConfig = null;
    supportsBondForget = null;
  }

  void wireOdometer(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
  }) {
    refreshOdometer(chars, onUpdate: onUpdate);
  }

  void refreshOdometer(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
  }) {
    final characteristic = chars.odometerCharacteristic;
    if (characteristic == null) return;

    _log.info('Reading odometer');
    readOdometer(characteristic, (meters) {
      odometerMeters = meters;
      onUpdate();
    });
  }

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
